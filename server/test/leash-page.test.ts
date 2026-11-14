import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { cachedState } from "../src/leash-page.js";
import type { Chain, LeashState } from "../src/near.js";
import { memoryStore, type Receipt } from "../src/receipts.js";

const cfg = { ...loadConfig({ AIRKEY_OWNER: "airkey-harshal.testnet", AIRKEY_API_TOKEN: "secret-token" }) };
const today = Math.floor(Date.now() / 86_400_000);
const state: LeashState = {
  owner: "airkey-harshal.testnet",
  leash: "leash.airkey-harshal.testnet",
  paused: false,
  available: "1204999999999999999999999",
  agents: [{ account: "pay.airkey-harshal.testnet", agent: { tier: "trusted", per_payment_cap: "500000000000000000000000", daily_cap: "1000000000000000000000000", spent_today: "200000000000000000000000", day: today } }],
  allowlist: ["friend.airkey-harshal.testnet"],
  blocklist: [{ account: "drain.airkey-harshal.testnet", reason: "asked for an urgent payment" }],
  pending: [{ id: 3, agent: "inbox.airkey-harshal.testnet", receiver: "vendor.airkey-harshal.testnet", amount: "400000000000000000000000", memo: "logo", rule: "R6", reason: "not on your allowlist", created_at_ns: 0 }],
};

function setup() {
  let reads = 0;
  const chain = { state: async () => (reads++, state) } as unknown as Chain;
  const receipts = memoryStore();
  const r: Receipt = {
    id: "r1",
    at: "2026-11-14T10:00:00.000Z",
    input: { text: "pay harshal 0.2 for dinner SECRET-WORDS", source: "typed" },
    interpretation: { action: { kind: "pay", receiver: "harshal", amountNear: "0.2", memo: "dinner" }, reader: "rules" },
    agent: { account: "pay.airkey-harshal.testnet", tier: "trusted" },
    receiver: { asked: "harshal", account: "friend.airkey-harshal.testnet", via: "contacts" },
    outcome: "paid",
    message: "Paid 0.2 NEAR to friend.airkey-harshal.testnet",
    tx: { hash: "HASH1", url: "https://testnet.nearblocks.io/txns/HASH1" },
  };
  receipts.add(r);
  receipts.add({ ...r, id: "r2", outcome: "blocked", input: { text: "pay drain 5", source: "pasted" }, agent: { account: "inbox.airkey-harshal.testnet", tier: "untrusted" }, receiver: { asked: "drain", account: "drain.airkey-harshal.testnet", via: "contacts" }, decision: { status: "blocked", rule: "R3", reason: "blocked", pending_id: null }, tx: { hash: "HASH2", url: "https://testnet.nearblocks.io/txns/HASH2" } });
  const app = buildApp({ cfg, chain, receipts });
  return { app, reads: () => reads };
}

describe("GET /leash", () => {
  it("works without a token, while /v1/state still needs one", async () => {
    const { app } = setup();
    const page = await app.inject({ method: "GET", url: "/leash" });
    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toMatch(/text\/html/);
    expect((await app.inject({ method: "GET", url: "/leash?x=1" })).statusCode).toBe(200);
    expect((await app.inject({ method: "GET", url: "/v1/state" })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/v1/receipts" })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/v1/state", headers: { authorization: "Bearer secret-token" } })).statusCode).toBe(200);
  });

  it("shows the leash from chain and plain lines for the receipts, with nothing private", async () => {
    const { app } = setup();
    const html = (await app.inject({ method: "GET", url: "/leash" })).body;
    expect(html).toContain("AIRKEY: AI agents in your keyboard.");
    expect(html).toContain("github.com/harshalbhangale/near-hack");
    expect(html).toContain("1.20");
    expect(html).toContain("Pay Agent");
    expect(html).toContain("drain.airkey-harshal.testnet");
    expect(html).toContain("friend.airkey-harshal.testnet");
    expect(html).toContain("vendor.airkey-harshal.testnet");
    expect(html).toContain("Paid 0.2 NEAR to harshal");
    expect(html).toContain("Blocked: drain is on your blocked list");
    expect(html).toContain("https://testnet.nearblocks.io/txns/HASH2");
    expect(html).not.toContain("SECRET-WORDS");
    expect(html).not.toContain("secret-token");
    expect(html).not.toMatch(/<script/i);
  });

  it("reads the chain at most once per 15 seconds", async () => {
    let t = 0;
    let reads = 0;
    const read = cachedState({ state: async () => (reads++, state) }, 15_000, () => t);
    await read();
    t = 14_000;
    await read();
    expect(reads).toBe(1);
    t = 15_001;
    await read();
    expect(reads).toBe(2);
    const { app, reads: appReads } = setup();
    await app.inject({ method: "GET", url: "/leash" });
    await app.inject({ method: "GET", url: "/leash" });
    expect(appReads()).toBe(1);
  });
});
