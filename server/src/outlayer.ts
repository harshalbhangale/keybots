// Sign the agents' leash calls inside OutLayer's TEE instead of with local keys.
// On with AIRKEY_SIGNER=outlayer. The server holds only OutLayer API keys
// (wk_..., in server/.env); the agents' NEAR keys stay in OutLayer's keystore.
// Reads still go through near.ts. Only pay and swap change who signs.
import type { Config } from "./config.js";
import type { Chain, Decision } from "./near.js";

export interface OutLayerOptions {
  /** OutLayer API base. Testnet: https://testnet-api.outlayer.ai */
  api: string;
  /** NEAR RPC, to read the transaction OutLayer sent. */
  rpc: string;
  /** Agent account -> its OutLayer API key. */
  keys: Record<string, string>;
  fetch: typeof fetch;
  pollMs: number;
  timeoutMs: number;
}

const ROLES = { TRUSTED: "trusted", UNTRUSTED: "untrusted", TRADE: "trade" } as const;

/** Map each agent account to its key from OUTLAYER_KEY_TRUSTED / _UNTRUSTED / _TRADE. */
export function outlayerKeys(cfg: Config, env = process.env): Record<string, string> {
  const keys: Record<string, string> = {};
  for (const [suffix, role] of Object.entries(ROLES)) {
    const key = env[`OUTLAYER_KEY_${suffix}`];
    if (key) keys[cfg.agents[role]] = key;
  }
  return keys;
}

export class OutLayerError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

interface CallResponse {
  request_id: string;
  status: string;
  tx_hash?: string | null;
  approval_id?: string | null;
}

interface TxOutcome {
  transaction: { hash: string };
  status: { SuccessValue?: string; Failure?: unknown };
  transaction_outcome: { outcome: { logs: string[] } };
  receipts_outcome: { outcome: { logs: string[] } }[];
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function outlayerChain(cfg: Config, base: Chain, opts: Partial<OutLayerOptions> = {}): Chain {
  const o: OutLayerOptions = {
    api: (opts.api ?? process.env.OUTLAYER_API ?? "https://testnet-api.outlayer.ai").replace(/\/$/, ""),
    rpc: opts.rpc ?? cfg.rpc,
    keys: opts.keys ?? outlayerKeys(cfg),
    fetch: opts.fetch ?? fetch,
    pollMs: opts.pollMs ?? 1000,
    timeoutMs: opts.timeoutMs ?? 60_000,
  };
  if (cfg.network !== "testnet" && process.env.AIRKEY_OUTLAYER_MAINNET !== "yes") {
    throw new Error("OutLayer custody is testnet-only for now");
  }

  async function api<T>(key: string, method: string, path: string, body?: object): Promise<T> {
    const res = await o.fetch(`${o.api}${path}`, {
      method,
      headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(o.timeoutMs),
    });
    const text = await res.text();
    let json: Record<string, unknown> = {};
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      json = { message: text.slice(0, 200) };
    }
    if (!res.ok) {
      const code = String(json.error ?? "http_error");
      throw new OutLayerError(res.status, code, `OutLayer ${res.status} ${code}: ${String(json.message ?? "")}`.trim());
    }
    return json as T;
  }

  /** Ask OutLayer to send the call, waiting out a busy wallet and an unfinished request. */
  async function send(key: string, methodName: string, args: object, gas: bigint): Promise<string> {
    const body = { receiver_id: cfg.leash, method_name: methodName, args, gas: gas.toString(), deposit: "0" };
    const deadline = Date.now() + o.timeoutMs;
    let r: CallResponse | null = null;
    while (!r) {
      try {
        r = await api<CallResponse>(key, "POST", "/wallet/v1/call", body);
      } catch (e) {
        if (!(e instanceof OutLayerError && e.code === "wallet_busy") || Date.now() > deadline) throw e;
        await sleep(o.pollMs);
      }
    }
    if (r.status === "pending_approval") throw new Error(`OutLayer is holding this call for approval (${r.approval_id})`);
    while (!r.tx_hash) {
      if (["failed", "rejected", "cancelled", "refunded"].includes(r.status)) throw new Error(`OutLayer request ${r.request_id} ${r.status}`);
      if (Date.now() > deadline) throw new Error(`OutLayer request ${r.request_id} still ${r.status}`);
      await sleep(o.pollMs);
      r = await api<CallResponse>(key, "GET", `/wallet/v1/requests/${r.request_id}`);
    }
    return r.tx_hash;
  }

  async function outcome(txHash: string, sender: string): Promise<TxOutcome> {
    const res = await o.fetch(o.rpc, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: "airkey", method: "tx", params: { tx_hash: txHash, sender_account_id: sender, wait_until: "EXECUTED_OPTIMISTIC" } }),
      signal: AbortSignal.timeout(o.timeoutMs),
    });
    const j = (await res.json()) as { result?: TxOutcome; error?: { message?: string; data?: unknown } };
    if (!j.result) throw new Error(`RPC tx ${txHash}: ${j.error?.message ?? "no result"}`);
    return j.result;
  }

  /** Same result shape as near.ts: the leash's decision, every log line and the airkey events. */
  async function callLeash(agent: string, methodName: string, args: object, gas: bigint) {
    const key = o.keys[agent];
    if (!key) throw new Error(`No OutLayer key for ${agent}`);
    const txHash = await send(key, methodName, args, gas);
    const res = await outcome(txHash, agent);
    if (res.status.Failure) throw new Error(`Leash call failed: ${JSON.stringify(res.status.Failure)}`);
    const v = res.status.SuccessValue;
    const decision = JSON.parse(Buffer.from(v ?? "", "base64").toString() || "null") as Decision;
    const logs = [res.transaction_outcome, ...res.receipts_outcome].flatMap((x) => x.outcome.logs);
    const events = logs.filter((l) => l.startsWith("EVENT_JSON:")).map((l) => JSON.parse(l.slice(11)));
    return { decision, txHash: res.transaction.hash, events, logs };
  }

  return {
    ...base,
    async pay(agent, args) {
      const { decision, txHash, events } = await callLeash(agent, "pay", args, 50_000_000_000_000n);
      return { decision, txHash, events };
    },
    swap: (agent, args) => callLeash(agent, "swap", args, 200_000_000_000_000n),
  };
}
