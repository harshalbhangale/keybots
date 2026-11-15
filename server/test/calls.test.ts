import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileCalls, memoryCalls, readCall, routeCall } from "../src/calls.js";
import { loadConfig } from "../src/config.js";

const tokens = {
  NEAR: { assetId: "nep141:wrap.near", symbol: "NEAR", blockchain: "near", decimals: 24, price: 3.5 },
  AURORA: { assetId: "nep141:aaaaaa20d9e0e2461697782ef11675f668207961.factory.bridge.near", symbol: "AURORA", blockchain: "near", decimals: 18, price: 0.1 },
  SOL: { assetId: "nep141:sol.omft.near", symbol: "SOL", blockchain: "sol", decimals: 9, price: 80 },
} as const;
const intents = {
  pick: async (asked: string) => {
    const token = tokens[asked.toUpperCase() as keyof typeof tokens];
    return token ? { asked, verified: true, token, alsoOn: [], reason: "ok" } : { asked, verified: false, alsoOn: [], reason: `${asked} isn't on NEAR Intents` };
  },
  quote: async (_from: unknown, to: { symbol: string }, amount: string) => ({ amountOutFormatted: to.symbol === "SOL" ? "0.0248" : "1", amountOutUsd: "1.98", amountIn: amount }),
};
const trader = { tier: "trusted" as const, per_payment_cap: (10n ** 24n).toString(), daily_cap: (2n * 10n ** 24n).toString(), spent_today: (5n * 10n ** 23n).toString(), day: 1 };
const chain = {
  state: async () => ({ owner: "x.testnet", leash: "leash.x.testnet", paused: false, available: "1", agents: [{ account: "trader.x.testnet", agent: trader }], allowlist: [], blocklist: [] }),
};
const rhea = { route: (s: string) => (["USDC", "USDT"].includes(s.toUpperCase()) ? { pool: 1 } : undefined) };
const deps = { intents: intents as never, chain: chain as never, tradeAgent: "trader.x.testnet", network: "testnet", rhea };

describe("reading a copied call", () => {
  it("reads a bullish cashtag call", () => {
    expect(readCall("$NEAR breakout, loading up here 🚀")).toMatchObject({ isCall: true, asset: "NEAR", direction: "bullish", instrument: "spot", confidence: "medium" });
    expect(readCall("buying $NEAR now")).toMatchObject({ confidence: "high" });
  });

  it("leaves ordinary words alone", () => {
    expect(readCall("we're near the top, lower from here").isCall).toBe(false);
    expect(readCall("see you at 7").isCall).toBe(false);
    expect(readCall("send me $5 for lunch").isCall).toBe(false);
  });

  it("knows a perp call and a horizon apart", () => {
    expect(readCall("long $NEAR 10x")).toMatchObject({ instrument: "perp", leverage: 10 });
    // A price target isn't leverage.
    expect(readCall("🚀 $NEARMOON just launched on NEAR, 100x incoming!! Aping in now")).toMatchObject({ instrument: "spot", leverage: null });
    expect(readCall("$SOL could be a 10x from here, buying")).toMatchObject({ instrument: "spot" });
    expect(readCall("$ETH 20x long")).toMatchObject({ instrument: "perp", leverage: 20 });
    expect(readCall("$NEAR is bullish long term")).toMatchObject({ instrument: "spot", direction: "bullish" });
  });
});

describe("routing a call", () => {
  it("offers a small buy of a real token, with the Trading Agent's caps", async () => {
    const text = "$NEAR breakout, loading up 🚀";
    const r = await routeCall(text, readCall(text), deps);
    expect(r).toMatchObject({
      status: "available",
      side: "buy",
      command: "buy $1 of near",
      title: "Buy $1 of NEAR",
      token: { symbol: "NEAR" },
      caps: { agent: "trader.x.testnet", perTrade: "1", leftToday: "1.5", paused: false, within: true },
      standIn: null,
    });
  });

  it("on testnet, shows the real NEAR Intents quote for SOL and says the hold swaps NEAR to USDC instead", async () => {
    const text = "$SOL breaking out, I'm buying";
    const r = await routeCall(text, readCall(text), deps);
    expect(r).toMatchObject({
      status: "available",
      title: "Buy $1 of SOL",
      command: "swap $1 of near to usdc",
      quote: { amountIn: "0.2857", amountOut: "0.0248", symbolOut: "SOL" },
      standIn: "Testnet has no SOL, so the hold swaps NEAR to USDC on Rhea instead.",
      caps: { within: true },
    });
  });

  it("on mainnet, buys the token itself", async () => {
    const text = "$SOL breaking out, I'm buying";
    const r = await routeCall(text, readCall(text), { ...deps, network: "mainnet" });
    expect(r).toMatchObject({ command: "swap $1 of near to sol", standIn: null });
  });

  it("says when the trade is over what's left today", async () => {
    const spent = { ...trader, spent_today: (19n * 10n ** 23n).toString() };
    const tight = { ...chain, state: async () => ({ ...(await chain.state()), agents: [{ account: "trader.x.testnet", agent: spent }] }) };
    const text = "$NEAR breakout 🚀";
    const r = await routeCall(text, readCall(text), { ...deps, chain: tight as never });
    expect(r).toMatchObject({ caps: { leftToday: "0.1", within: false } });
  });

  it("buys other tokens with NEAR, and moves NEAR to USDC on a bearish NEAR call", async () => {
    const a = "$AURORA looking strong, buying";
    expect(await routeCall(a, readCall(a), { ...deps, network: "mainnet" })).toMatchObject({ command: "swap $1 of near to aurora" });
    const b = "$NEAR top is in, selling";
    expect(await routeCall(b, readCall(b), deps)).toMatchObject({ side: "sell", command: "swap $1 of near to usdc" });
  });

  it("gives no route rather than a stand-in", async () => {
    const cases: [string, RegExp][] = [
      ["long $NEAR 10x", /perp call/],
      ["$FAKECOIN to the moon 🚀", /isn.t a token we could verify/],
      ["$AURORA is weak, dumping", /doesn't short/],
      ["$NEAR entry here", /doesn't say buy or sell/],
      ["$NEAR 🚀 0x1234567890abcdef1234567890abcdef12345678", /contract address/],
    ];
    for (const [text, reason] of cases) {
      const r = await routeCall(text, readCall(text), deps);
      expect(r.status, text).toBe("unavailable");
      expect(r.status === "unavailable" && r.reason, text).toMatch(reason);
    }
  });
});

describe("POST /v1/call", () => {
  const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
  const app = () => buildApp({ cfg, chain: chain as never, receipts: {} as never, intents: intents as never });

  it("returns the call and its route, and runs nothing", async () => {
    const r = await app().inject({ method: "POST", url: "/v1/call", payload: { text: "$NEAR breakout 🚀" } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ call: { isCall: true, asset: "NEAR" }, route: { status: "available", command: "buy $1 of near" } });
  });

  it("needs text", async () => {
    expect((await app().inject({ method: "POST", url: "/v1/call", payload: {} })).statusCode).toBe(400);
  });
});

describe("the calls book", () => {
  const call = (text: string) => readCall(text);
  const available = { status: "available", side: "buy", command: "buy $1 of near", title: "Buy $1 of NEAR", token: { symbol: "NEAR", assetId: "x", price: 3.5 }, quote: null, standIn: null, caps: null, note: "" } as const;

  it("keeps one record per call, and a re-check of an open call updates its route", () => {
    const book = memoryCalls();
    const text = "$NEAR breakout 🚀";
    const a = book.check(text, call(text), available, 3.5);
    expect(a).toMatchObject({ text, asset: "NEAR", direction: "bullish", status: "available", command: "buy $1 of near", verified: true, priceThen: 3.5, trade: null, dismissed: false });
    const b = book.check(text, call(text), { status: "unavailable", reason: "Token check failed: gone." }, 4);
    expect(b.id).toBe(a.id);
    expect(book.list()).toHaveLength(1);
    expect(book.list()[0]).toMatchObject({ status: "unavailable", reason: "Token check failed: gone.", command: null, priceThen: 3.5 });
  });

  it("links the trade a hold ran, and a traded call checked again is a new record", () => {
    const book = memoryCalls();
    const text = "$NEAR breakout 🚀";
    const a = book.check(text, call(text), available, 3.5);
    book.traded(a.id, { at: "2026-11-13T00:00:00.000Z", receiptId: "r1", outcome: "swapped", message: "Swapped.", tx: { hash: "h", url: "u" } });
    expect(book.get(a.id)?.trade).toMatchObject({ receiptId: "r1", outcome: "swapped", tx: { hash: "h" } });
    expect(book.traded("nope", { at: "", receiptId: "", outcome: "", message: "" })).toBeUndefined();
    const again = book.check(text, call(text), available, 3.6);
    expect(again.id).not.toBe(a.id);
    expect(book.list().map((c) => c.id)).toEqual([again.id, a.id]); // newest first
  });

  it("survives a restart on disk", () => {
    const dir = mkdtempSync(join(tmpdir(), "airkey-calls-"));
    const text = "$NEAR top is in, selling";
    const a = fileCalls(dir).check(text, call(text), available, 3.5);
    fileCalls(dir).dismiss(a.id);
    expect(fileCalls(dir).list()).toMatchObject([{ id: a.id, dismissed: true, direction: "bearish" }]);
    rmSync(dir, { recursive: true });
  });
});

describe("GET /v1/calls", () => {
  const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
  const priced = { ...intents, price: async (s: string) => (s === "NEAR" ? 3.85 : undefined) };
  const receipt = { id: "r1", at: "2026-11-13T00:00:00.000Z", outcome: "blocked", message: "Blocked by Spend Limits.", input: {}, interpretation: {} };

  it("lists every checked call with the price then and now, and skips what isn't a call", async () => {
    const app = buildApp({ cfg, chain: chain as never, receipts: {} as never, intents: priced as never });
    const a = (await app.inject({ method: "POST", url: "/v1/call", payload: { text: "$NEAR breakout 🚀" } })).json();
    expect(a.id).toEqual(expect.any(String));
    await app.inject({ method: "POST", url: "/v1/call", payload: { text: "long $NEAR 10x" } });
    const none = (await app.inject({ method: "POST", url: "/v1/call", payload: { text: "see you at 7" } })).json();
    expect(none.id).toBeUndefined();
    const { calls } = (await app.inject({ method: "GET", url: "/v1/calls" })).json();
    expect(calls).toHaveLength(2);
    expect(calls[0]).toMatchObject({ text: "long $NEAR 10x", status: "unavailable", reason: expect.stringMatching(/perp/), command: null, priceThen: 3.85, priceNow: 3.85, trade: null });
    expect(calls[1]).toMatchObject({ id: a.id, asset: "NEAR", direction: "bullish", confidence: "medium", status: "available", command: "buy $1 of near", priceThen: 3.5, priceNow: 3.85, trade: null });
  });

  it("records the trade when the hold's command carries the call's id", async () => {
    const calls = memoryCalls();
    const app = buildApp({ cfg, chain: chain as never, receipts: {} as never, intents: priced as never, calls });
    const { id } = (await app.inject({ method: "POST", url: "/v1/call", payload: { text: "$NEAR breakout 🚀" } })).json();
    // What POST /v1/command does once the command has run (running one needs the chain).
    calls.traded(id, { at: receipt.at, receiptId: receipt.id, outcome: receipt.outcome, message: receipt.message });
    const list = (await app.inject({ method: "GET", url: "/v1/calls" })).json().calls;
    expect(list[0].trade).toMatchObject({ outcome: "blocked", message: "Blocked by Spend Limits.", receiptId: "r1" });
  });

  it("puts a call away", async () => {
    const app = buildApp({ cfg, chain: chain as never, receipts: {} as never, intents: priced as never });
    const { id } = (await app.inject({ method: "POST", url: "/v1/call", payload: { text: "$NEAR breakout 🚀" } })).json();
    expect((await app.inject({ method: "POST", url: `/v1/calls/${id}/dismiss` })).json()).toMatchObject({ id, dismissed: true });
    expect((await app.inject({ method: "POST", url: "/v1/calls/nope/dismiss" })).statusCode).toBe(404);
  });
});
