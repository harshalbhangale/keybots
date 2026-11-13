// Everything the server does on NEAR: read the leash, and sign `pay` or `swap`
// as an agent. The server holds only the agents' function-call keys (scoped to
// the leash). It never holds the owner's key.
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { Account, JsonRpcProvider } from "near-api-js";
import type { Config } from "./config.js";

export interface Decision {
  status: "paid" | "pending" | "blocked";
  rule: string | null;
  reason: string;
  pending_id: number | null;
}

export interface AgentView {
  tier: "trusted" | "untrusted";
  per_payment_cap: string;
  daily_cap: string;
  spent_today: string;
  day: number;
}

export interface LeashState {
  owner: string;
  leash: string;
  paused: boolean;
  available: string;
  agents: { account: string; agent: AgentView }[];
  allowlist: string[];
  blocklist: { account: string; reason: string }[];
  pending: unknown[];
}

export interface AccountFacts {
  exists: boolean;
  isContract: boolean;
  createdAtNs: string | null;
}

/** The chain operations the rest of the server depends on (faked in tests). */
export interface Chain {
  state(): Promise<LeashState>;
  isAllowed(account: string): Promise<boolean>;
  blockedReason(account: string): Promise<string | null>;
  facts(account: string): Promise<AccountFacts>;
  pay(agent: string, args: { receiver: string; amount: string; memo?: string; ask_owner?: boolean }): Promise<{ decision: Decision; txHash: string; events: unknown[] }>;
  /** Ask the leash to swap NEAR at a venue (Rhea, or a NEAR Intents deposit address). `logs` has every log line, the venue's too. */
  swap(agent: string, args: { venue: string; amount: string; wrap: string; msg?: string; memo?: string }): Promise<{ decision: Decision; txHash: string; events: unknown[]; logs: string[] }>;
  txUrl(hash: string): string;
}

const EMPTY_CODE = "11111111111111111111111111111111";

function readKey(cfg: Config, accountId: string): string {
  const envName = `AIRKEY_KEY_${accountId.split(".")[0].toUpperCase().replace(/[^A-Z0-9]/g, "_")}`;
  if (process.env[envName]) return process.env[envName]!;
  const p = join(cfg.keysDir, `${accountId}.json`);
  if (!existsSync(p)) throw new Error(`No key for ${accountId}: set ${envName} or add ${p}`);
  return JSON.parse(readFileSync(p, "utf8")).secretKey;
}

export function nearChain(cfg: Config): Chain {
  const provider = new JsonRpcProvider({ url: cfg.rpc });
  const view = <T>(method: string, args: Record<string, unknown> = {}) =>
    provider.callFunction({ contractId: cfg.leash, method, args, blockQuery: { finality: "optimistic" } }) as Promise<T>;
  const signers = new Map<string, Account>();
  const agentAccount = (id: string) => {
    if (!signers.has(id)) signers.set(id, new Account(id, provider, readKey(cfg, id) as never));
    return signers.get(id)!;
  };

  /** Call the leash as an agent; returns its decision, every log line and the airkey events among them. */
  async function callLeash(agent: string, methodName: string, args: object, gas: bigint) {
    const res = (await agentAccount(agent).callFunctionRaw({ contractId: cfg.leash, methodName, args, gas })) as {
      transaction: { hash: string };
      status: { SuccessValue?: string };
      transaction_outcome: { outcome: { logs: string[] } };
      receipts_outcome: { outcome: { logs: string[] } }[];
    };
    const v = res.status?.SuccessValue;
    const decision = JSON.parse(Buffer.from(v ?? "", "base64").toString() || "null") as Decision;
    const logs = [res.transaction_outcome, ...res.receipts_outcome].flatMap((o) => o.outcome.logs);
    const events = logs.filter((l) => l.startsWith("EVENT_JSON:")).map((l) => JSON.parse(l.slice(11)));
    return { decision, txHash: res.transaction.hash, events, logs };
  }

  return {
    async state() {
      const [owner, paused, available, agents, allowlist, blocklist, pending] = await Promise.all([
        view<string>("get_owner"),
        view<boolean>("is_paused"),
        view<string>("available"),
        view<[string, AgentView][]>("list_agents"),
        view<string[]>("list_allowed"),
        view<[string, string][]>("list_blocked"),
        view<unknown[]>("list_pending"),
      ]);
      return {
        owner,
        leash: cfg.leash,
        paused,
        available,
        agents: agents.map(([account, agent]) => ({ account, agent })),
        allowlist,
        blocklist: blocklist.map(([account, reason]) => ({ account, reason })),
        pending,
      };
    },
    isAllowed: (account) => view<boolean>("is_allowed", { account }),
    blockedReason: async (account) => (await view<string | null>("blocked_reason", { account })) ?? null,
    async facts(account) {
      let exists = false;
      let isContract = false;
      try {
        const a = (await provider.viewAccount({ accountId: account, blockQuery: { finality: "final" } })) as { code_hash?: string };
        exists = true;
        isContract = !!a.code_hash && a.code_hash !== EMPTY_CODE;
      } catch {
        exists = false;
      }
      let createdAtNs: string | null = null;
      if (exists) {
        try {
          const r = await fetch(`${cfg.nearblocksApi}/accounts/${account}`, { signal: AbortSignal.timeout(4000) });
          const j = (await r.json()) as { data?: { created?: { block_timestamp?: string } } };
          createdAtNs = j.data?.created?.block_timestamp ?? null;
        } catch {
          createdAtNs = null;
        }
      }
      return { exists, isContract, createdAtNs };
    },
    async pay(agent, args) {
      const { decision, txHash, events } = await callLeash(agent, "pay", args, 50_000_000_000_000n);
      return { decision, txHash, events };
    },
    // A swap wraps NEAR, sends it on and waits for the venue: all the gas there is.
    swap: (agent, args) => callLeash(agent, "swap", args, 300_000_000_000_000n),
    txUrl: (hash) => `${cfg.explorer}/txns/${hash}`,
  };
}
