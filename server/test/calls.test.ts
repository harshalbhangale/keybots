import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { readCall, routeCall } from "../src/calls.js";
import { loadConfig } from "../src/config.js";

const tokens = {
  NEAR: { assetId: "nep141:wrap.near", symbol: "NEAR", blockchain: "near", decimals: 24, price: 3.5 },
  AURORA: { assetId: "nep141:aaaaaa20d9e0e2461697782ef11675f668207961.factory.bridge.near", symbol: "AURORA", blockchain: "near", decimals: 18, price: 0.1 },
} as const;
const intents = {
  pick: async (asked: string) => {
    const token = tokens[asked.toUpperCase() as keyof typeof tokens];
    return token ? { asked, verified: true, token, alsoOn: [], reason: "ok" } : { asked, verified: false, alsoOn: [], reason: `${asked} isn't on NEAR Intents` };
  },
};
const trader = { tier: "trusted" as const, per_payment_cap: (10n ** 24n).toString(), daily_cap: (2n * 10n ** 24n).toString(), spent_today: (5n * 10n ** 23n).toString(), day: 1 };
const chain = {
  state: async () => ({ owner: "x.testnet", leash: "leash.x.testnet", paused: false, available: "1", agents: [{ account: "trader.x.testnet", agent: trader }], allowlist: [], blocklist: [] }),
};
const deps = { intents: intents as never, chain: chain as never, tradeAgent: "trader.x.testnet" };

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
      command: "buy $2 of near",
      title: "Buy $2 of NEAR",
      token: { symbol: "NEAR" },
      caps: { agent: "trader.x.testnet", perTrade: "1", leftToday: "1.5", paused: false },
    });
  });

  it("buys other tokens with NEAR, and moves NEAR to USDC on a bearish NEAR call", async () => {
    const a = "$AURORA looking strong, buying";
    expect(await routeCall(a, readCall(a), deps)).toMatchObject({ command: "swap $2 of near to aurora" });
    const b = "$NEAR top is in, selling";
    expect(await routeCall(b, readCall(b), deps)).toMatchObject({ side: "sell", command: "swap $2 of near to usdc" });
  });

  it("gives no route rather than a stand-in", async () => {
    const cases: [string, RegExp][] = [
      ["long $NEAR 10x", /perp call/],
      ["$FAKECOIN to the moon 🚀", /Token check failed/],
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
    expect(r.json()).toMatchObject({ call: { isCall: true, asset: "NEAR" }, route: { status: "available", command: "buy $2 of near" } });
  });

  it("needs text", async () => {
    expect((await app().inject({ method: "POST", url: "/v1/call", payload: {} })).statusCode).toBe(400);
  });
});
