import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import type { Chain } from "../src/near.js";
import { outlayerChain, outlayerKeys } from "../src/outlayer.js";

const PAY = "a".repeat(64);
const INBOX = "b".repeat(64);
const KEY_PAY = "wk_test_pay";
const KEY_INBOX = "wk_test_inbox";

const b64 = (v: unknown) => Buffer.from(JSON.stringify(v)).toString("base64");
const event = (name: string, data: object) => `EVENT_JSON:${JSON.stringify({ standard: "airkey", version: "1.0.0", event: name, data: [data] })}`;

/**
 * One fake server plays OutLayer (/wallet/v1/*) and NEAR RPC (POST /rpc).
 * Its "leash" pays an allowlisted receiver and blocks drain.testnet (R3).
 */
type Seen = { auth?: string; path: string; body: Record<string, unknown> };
const seen: Seen[] = [];
let mode: "ok" | "busy-once" | "processing" | "approval" | "bad-key" = "ok";
let busyLeft = 0;
const txs = new Map<string, { sender: string; method: string; args: Record<string, unknown> }>();
let server: Server;
let base = "";

function read(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((resolve) => {
    let s = "";
    req.on("data", (c) => (s += c));
    req.on("end", () => resolve(s ? JSON.parse(s) : {}));
  });
}

function leashOutcome(hash: string) {
  const tx = txs.get(hash)!;
  const { receiver, amount } = tx.args as { receiver: string; amount: string };
  if (tx.method === "swap") {
    const d = { status: "paid", rule: null, reason: "Within your rules", pending_id: null };
    return { d, logs: [event("swap", { agent: tx.sender, venue: tx.args.venue, amount: tx.args.amount }), "Swapped 1 wrap.testnet for 2 usdt"] };
  }
  if (receiver === "drain.testnet") {
    const d = { status: "blocked", rule: "R3", reason: "Blocked: reported scam", pending_id: null };
    return { d, logs: [event("blocked", { agent: tx.sender, receiver, amount, rule: "R3" })] };
  }
  const d = { status: "paid", rule: null, reason: "Within your rules", pending_id: null };
  return { d, logs: [event("paid", { agent: tx.sender, receiver, amount })] };
}

beforeAll(async () => {
  server = createServer(async (req, res) => {
    const body = await read(req);
    const url = req.url ?? "";
    seen.push({ auth: req.headers.authorization, path: `${req.method} ${url}`, body });
    const send = (code: number, v: unknown) => {
      res.writeHead(code, { "content-type": "application/json" });
      res.end(JSON.stringify(v));
    };
    if (url === "/rpc") {
      const { tx_hash, sender_account_id } = body.params as { tx_hash: string; sender_account_id: string };
      const tx = txs.get(tx_hash);
      if (!tx || tx.sender !== sender_account_id) return send(200, { jsonrpc: "2.0", id: body.id, error: { message: "UNKNOWN_TRANSACTION" } });
      const { d, logs } = leashOutcome(tx_hash);
      return send(200, {
        jsonrpc: "2.0",
        id: body.id,
        result: {
          transaction: { hash: tx_hash },
          status: { SuccessValue: b64(d) },
          transaction_outcome: { outcome: { logs: [] } },
          receipts_outcome: [{ outcome: { logs } }],
        },
      });
    }
    const sender = req.headers.authorization === `Bearer ${KEY_PAY}` ? PAY : req.headers.authorization === `Bearer ${KEY_INBOX}` ? INBOX : null;
    if (!sender || mode === "bad-key") return send(401, { error: "invalid_api_key", message: "Invalid API key" });
    if (url === "/wallet/v1/call") {
      if (mode === "busy-once" && busyLeft-- > 0) return send(409, { error: "wallet_busy", message: "busy", in_flight_request_id: null, in_flight_operation: "call" });
      if (mode === "approval") return send(200, { request_id: "r-1", status: "pending_approval", approval_id: "ap-1" });
      const hash = `TX${txs.size + 1}`;
      txs.set(hash, { sender, method: String(body.method_name), args: body.args as Record<string, unknown> });
      if (mode === "processing") return send(200, { request_id: hash, status: "processing", tx_hash: null });
      return send(200, { request_id: `req-${hash}`, status: "success", tx_hash: hash });
    }
    const m = url.match(/^\/wallet\/v1\/requests\/(.+)$/);
    if (m) return send(200, { request_id: m[1], type: "call", status: "success", tx_hash: m[1] });
    send(404, { error: "bad_request", message: "no route" });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(() => new Promise<void>((r) => server.close(() => r())));

beforeEach(() => {
  seen.length = 0;
  mode = "ok";
});

const cfg = loadConfig({ AIRKEY_AGENT_TRUSTED: PAY, AIRKEY_AGENT_UNTRUSTED: INBOX } as NodeJS.ProcessEnv);
const local: Chain = {
  state: async () => ({ owner: "o", leash: cfg.leash, paused: false, available: "0", agents: [], allowlist: [], blocklist: [], pending: [] }),
  isAllowed: async () => false,
  blockedReason: async () => null,
  facts: async () => ({ exists: true, isContract: false, createdAtNs: null }),
  pay: async () => {
    throw new Error("local signer must not be used");
  },
  swap: async () => {
    throw new Error("local signer must not be used");
  },
  txUrl: (h) => `https://testnet.nearblocks.io/txns/${h}`,
};
const chain = () => outlayerChain(cfg, local, { api: base, rpc: `${base}/rpc`, keys: { [PAY]: KEY_PAY, [INBOX]: KEY_INBOX }, pollMs: 5, timeoutMs: 2000 });

describe("outlayer signer", () => {
  it("sends pay to the leash through /wallet/v1/call and returns the leash's decision", async () => {
    const r = await chain().pay(PAY, { receiver: "friend.testnet", amount: "100", memo: "lunch" });
    expect(r.decision.status).toBe("paid");
    expect(r.txHash).toBe("TX1");
    expect(r.events).toEqual([{ standard: "airkey", version: "1.0.0", event: "paid", data: [{ agent: PAY, receiver: "friend.testnet", amount: "100" }] }]);
    const call = seen.find((s) => s.path === "POST /wallet/v1/call")!;
    expect(call.auth).toBe(`Bearer ${KEY_PAY}`);
    expect(call.body).toEqual({
      receiver_id: cfg.leash,
      method_name: "pay",
      args: { receiver: "friend.testnet", amount: "100", memo: "lunch" },
      gas: "50000000000000",
      deposit: "0",
    });
  });

  it("returns the leash's block for a pasted scam", async () => {
    const r = await chain().pay(INBOX, { receiver: "drain.testnet", amount: "100" });
    expect(r.decision).toMatchObject({ status: "blocked", rule: "R3" });
    expect(r.events[0]).toMatchObject({ event: "blocked" });
    expect(seen.find((s) => s.path === "POST /wallet/v1/call")!.auth).toBe(`Bearer ${KEY_INBOX}`);
  });

  it("uses each agent's own key", async () => {
    await chain().pay(INBOX, { receiver: "friend.testnet", amount: "1" });
    expect(seen.find((s) => s.path === "POST /wallet/v1/call")!.auth).toBe(`Bearer ${KEY_INBOX}`);
  });

  it("sends swap with 200 TGas and returns every log line", async () => {
    const r = await chain().swap(PAY, { venue: "v.testnet", amount: "1", wrap: "wrap.testnet", msg: "{}" });
    expect(r.decision.status).toBe("paid");
    expect(r.logs).toContain("Swapped 1 wrap.testnet for 2 usdt");
    expect(seen.find((s) => s.path === "POST /wallet/v1/call")!.body).toMatchObject({ method_name: "swap", gas: "200000000000000" });
  });

  it("waits out a busy wallet", async () => {
    mode = "busy-once";
    busyLeft = 1;
    const r = await chain().pay(PAY, { receiver: "friend.testnet", amount: "1" });
    expect(r.decision.status).toBe("paid");
    expect(seen.filter((s) => s.path === "POST /wallet/v1/call")).toHaveLength(2);
  });

  it("polls a request that is still processing", async () => {
    mode = "processing";
    const r = await chain().pay(PAY, { receiver: "friend.testnet", amount: "1" });
    expect(r.decision.status).toBe("paid");
    expect(seen.some((s) => s.path.startsWith("GET /wallet/v1/requests/"))).toBe(true);
  });

  it("refuses an agent it has no key for, without calling OutLayer", async () => {
    await expect(chain().pay("stranger.testnet", { receiver: "friend.testnet", amount: "1" })).rejects.toThrow(/No OutLayer key/);
    expect(seen).toHaveLength(0);
  });

  it("surfaces OutLayer errors and approval holds", async () => {
    mode = "bad-key";
    await expect(chain().pay(PAY, { receiver: "friend.testnet", amount: "1" })).rejects.toThrow(/401 invalid_api_key/);
    mode = "approval";
    await expect(chain().pay(PAY, { receiver: "friend.testnet", amount: "1" })).rejects.toThrow(/approval/);
  });

  it("keeps reads on the local chain", async () => {
    const c = chain();
    expect(await c.state()).toMatchObject({ leash: cfg.leash });
    expect(c.txUrl("H")).toBe("https://testnet.nearblocks.io/txns/H");
    expect(seen).toHaveLength(0);
  });

  it("maps OUTLAYER_KEY_* env vars to the configured agents", () => {
    const env = { OUTLAYER_KEY_TRUSTED: "wk_a", OUTLAYER_KEY_UNTRUSTED: "wk_b" } as NodeJS.ProcessEnv;
    expect(outlayerKeys(cfg, env)).toEqual({ [PAY]: "wk_a", [INBOX]: "wk_b" });
  });

  it("will not run against mainnet", () => {
    const main = loadConfig({ NEAR_NETWORK: "mainnet" } as NodeJS.ProcessEnv);
    expect(() => outlayerChain(main, local, { keys: {} })).toThrow(/testnet-only/);
  });
});
