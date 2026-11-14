import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { parse } from "../src/parse.js";
import { orderFor, quoter, rheaHops, type PoolReturn } from "../src/quote.js";
import { RHEA } from "../src/rhea.js";

const NEAR24 = 10n ** 24n;
const list = [
  { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: 2 },
  { assetId: "nep141:usdc.near", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 },
  { assetId: "nep141:usdt.near", symbol: "USDT", blockchain: "near", decimals: 6, price: 1 },
  { assetId: "nep141:sol.omft.near", symbol: "SOL", blockchain: "sol", decimals: 9, price: 100 },
  { assetId: "nep141:eth.omft.near", symbol: "ETH", blockchain: "eth", decimals: 18, price: 3000 },
];
const cfg = { network: "testnet" as const, leash: "leash.x.testnet", agents: { trusted: "pay.x.testnet", untrusted: "inbox.x.testnet", trade: "trader.x.testnet" }, mainnetUsdCap: 0.15 };
const trader = { tier: "trusted" as const, per_payment_cap: NEAR24.toString(), daily_cap: (2n * NEAR24).toString(), spent_today: ((5n * NEAR24) / 10n).toString(), day: 1 };
const state = (over: object = {}) => ({
  owner: "x.testnet",
  leash: cfg.leash,
  paused: false,
  available: ((12n * NEAR24) / 10n).toString(),
  agents: [{ account: cfg.agents.trade, agent: trader }],
  allowlist: [],
  blocklist: [],
  pending: [],
  ...over,
});

/** A pool that pays 2.1 tokens a NEAR (and the other way round), less 0.1% for each whole NEAR of size. */
const pool: PoolReturn = async (_pool, tokenIn, _out, amountIn) => {
  const inNear = tokenIn === "wrap.testnet";
  const size = Number(BigInt(amountIn) / 10n ** 15n) / 1e9;
  const out = inNear ? size * 2.1 * (1 - size * 0.001) : (size / 2.1) * (1 - size * 0.001);
  return (BigInt(Math.round(out * 1e9)) * 10n ** 15n).toString();
};
const calls: string[] = [];
function make(over: { state?: object; network?: "testnet" | "mainnet"; quote?: () => Promise<unknown>; tokenCap?: string | null } = {}) {
  const mainnet = over.network === "mainnet";
  return quoter({
    cfg: { ...cfg, network: over.network ?? "testnet" },
    // The owner's rule for selling a token: 2 of it a trade unless a test says otherwise (null: no rule).
    chain: {
      state: async () => state(over.state) as never,
      tokenCap: async () => (over.tokenCap === null ? null : { max_per_trade: over.tokenCap ?? (2n * NEAR24).toString() }),
    },
    intents: {
      tokens: async () => list,
      quote: (async (from: { symbol: string }, to: { symbol: string }, amount: string) => {
        calls.push(`${amount} ${from.symbol}>${to.symbol}`);
        if (over.quote) return over.quote();
        return { dry: true, amountIn: "0", amountInFormatted: amount, amountInUsd: "1.00", amountOut: "9900000", amountOutFormatted: "0.0099", amountOutUsd: "0.99", minAmountOut: "9801000", timeEstimate: 20 };
      }) as never,
    },
    rhea: mainnet
      ? { network: undefined, holdings: async () => [] }
      : {
          network: RHEA.testnet,
          holdings: async () => [
            { symbol: "USDC", token: "usdc.itachicara.testnet", amount: "3.5" },
            { symbol: "USDT", token: "usdt.itachicara.testnet", amount: "0" },
          ],
        },
    poolReturn: mainnet ? undefined : pool,
  });
}

describe("the pools a pair goes through", () => {
  it("one pool with NEAR on either side, the shared pool between two tokens, none for a token Rhea doesn't have", () => {
    expect(rheaHops(RHEA.testnet, "NEAR", "USDC")?.hops.map((h) => h.pool)).toEqual([1103]);
    expect(rheaHops(RHEA.testnet, "USDC", "NEAR")?.hops).toEqual([{ pool: 1103, tokenIn: "usdc.itachicara.testnet", tokenOut: "wrap.testnet" }]);
    expect(rheaHops(RHEA.testnet, "USDC", "USDT")?.hops).toEqual([{ pool: 1126, tokenIn: "usdc.itachicara.testnet", tokenOut: "usdt.itachicara.testnet" }]);
    expect(rheaHops(RHEA.testnet, "NEAR", "SOL")).toBeNull();
    expect(rheaHops(undefined, "NEAR", "USDC")).toBeNull();
  });
});

describe("a quote for the trade panel", () => {
  it("NEAR to USDC on Rhea: every number from the pool, the list and the leash", async () => {
    const q = await make().quote({ from: "near", to: "usdc", amount: "0.50" });
    expect(q).toMatchObject({
      from: { symbol: "NEAR", assetId: "nep141:wrap.near", price: 2, verified: true },
      to: { symbol: "USDC", assetId: "nep141:usdc.near", price: 1, verified: true },
      amountIn: "0.5",
      amountOut: "1.049",
      rate: "1 NEAR = 2.099 USDC",
      minReceived: "1.039",
      slippagePct: 1,
      route: { venue: "Rhea", pool: 1103, pools: [1103] },
      executable: true,
      reason: null,
      networkFee: { amount: "0.0024", symbol: "NEAR", usd: "0.0048" },
      valueUsd: "1.00",
      caps: { agent: "trader.x.testnet", perTrade: "1", leftToday: "1.5", paused: false, valueNear: "0.5", within: true },
      balance: { symbol: "NEAR", amount: "1.2", enough: true },
      command: "swap 0.5 near to usdc",
      problem: null,
      ready: true,
    });
    // 0.5 NEAR moves this pool 0.05% against a thousandth of the size.
    expect(q.priceImpact).toBeCloseTo(0.05, 2);
    // 1.049 USDC for $1 of NEAR at NEAR Intents' prices.
    expect(q.vsMarket).toBeCloseTo(4.95, 1);
  });

  it("the command it gives is one the rules read back as the same swap", async () => {
    const q = await make().quote({ from: "NEAR", to: "USDT", amount: "0.25" });
    expect(parse(q.command)).toEqual({ kind: "swap", amount: "0.25", from: "NEAR", to: "USDT" });
  });

  it("a token back to NEAR, and token to token in their shared pool, are executable when the leash has a rule for the token", async () => {
    const back = await make().quote({ from: "USDC", to: "NEAR", amount: "1.05" });
    expect(back).toMatchObject({ route: { venue: "Rhea", pools: [1103] }, executable: true, command: "swap 1.05 usdc to near", balance: { symbol: "USDC", amount: "3.5", enough: true }, ready: true });
    expect(Number(back.amountOut)).toBeCloseTo(0.4995, 3);
    // $2.50 of USDC is 1.25 NEAR at NEAR Intents' price: over the 1 NEAR per-trade cap.
    const big = await make({ tokenCap: (5n * NEAR24).toString() }).quote({ from: "USDC", to: "NEAR", amount: "2.5" });
    expect(big).toMatchObject({ caps: { within: false, valueNear: "1.25" }, ready: false, problem: "Over your 1 NEAR per-trade limit: this is worth about 1.25 NEAR." });
    const across = await make().quote({ from: "USDC", to: "USDT", amount: "1" });
    expect(across).toMatchObject({ route: { venue: "Rhea", pool: 1126, pools: [1126] }, executable: true, command: "swap 1 usdc to usdt" });
  });

  it("a token sale the leash has no rule for is Rhea's quote only, and one over the rule says so", async () => {
    const none = await make({ tokenCap: null }).quote({ from: "USDC", to: "NEAR", amount: "1.05" });
    expect(none).toMatchObject({
      route: { venue: "Rhea", pools: [1103] },
      executable: false,
      ready: false,
      reason: "Spend Limits can't sell USDC yet. Its owner sets that up; this is Rhea's live quote.",
      command: "swap 1.05 usdc to near",
    });
    expect(Number(none.amountOut)).toBeCloseTo(0.4995, 3);
    const over = await make().quote({ from: "USDC", to: "NEAR", amount: "2.1" });
    expect(over).toMatchObject({ executable: false, reason: "Over your limit of 2 USDC a trade." });
  });

  it("says in one line why the hold is off: over a cap, over today's, not enough, paused", async () => {
    expect((await make().quote({ from: "NEAR", to: "USDC", amount: "1.1" })).problem).toBe("Over your 1 NEAR per-trade limit: this is worth about 1.1 NEAR.");
    const spent = { agents: [{ account: cfg.agents.trade, agent: { ...trader, spent_today: ((18n * NEAR24) / 10n).toString() } }] };
    expect(await make({ state: spent }).quote({ from: "NEAR", to: "USDC", amount: "0.5" })).toMatchObject({
      ready: false,
      caps: { leftToday: "0.2", within: false },
      problem: "Only 0.2 NEAR is left of today's limit; this is worth about 0.5 NEAR.",
    });
    expect(await make({ state: { available: (NEAR24 / 10n).toString() } }).quote({ from: "NEAR", to: "USDC", amount: "0.5" })).toMatchObject({
      ready: false,
      balance: { amount: "0.1", enough: false },
      problem: "Not enough NEAR: Spend Limits holds 0.1.",
    });
    expect(await make({ state: { paused: true } }).quote({ from: "NEAR", to: "USDC", amount: "0.5" })).toMatchObject({
      ready: false,
      problem: "The kill switch is on. Nothing trades until you turn it off.",
    });
  });

  it("falls back to the Payment Agent's caps when the leash has no Trading Agent", async () => {
    const q = await make({ state: { agents: [{ account: cfg.agents.trusted, agent: trader }] } }).quote({ from: "NEAR", to: "USDC", amount: "0.5" });
    expect(q.caps?.agent).toBe("pay.x.testnet");
  });

  it("a token testnet doesn't have: NEAR Intents' dry quote, not executable, and it says why", async () => {
    calls.length = 0;
    const q = await make().quote({ from: "NEAR", to: "SOL", amount: "0.5" });
    expect(calls).toEqual(["0.5 wNEAR>SOL"]);
    expect(q).toMatchObject({
      amountOut: "0.0099",
      minReceived: "0.009801",
      route: { venue: "NEAR Intents", seconds: 20 },
      executable: false,
      ready: false,
      reason: "Testnet has no SOL. This is NEAR Intents' live mainnet quote; nothing would be sent.",
      priceImpact: 1,
      valueUsd: "1.00",
      command: "swap 0.5 near to sol",
    });
    expect(q.problem).toBe(q.reason);
  });

  it("a Rhea-routed quote never waits on NEAR Intents' quote", async () => {
    calls.length = 0;
    await make().quote({ from: "NEAR", to: "USDC", amount: "0.5" });
    expect(calls).toEqual([]);
  });

  it("still quotes when the leash's state doesn't come back: no caps, no balance", async () => {
    const q = await quoter({
      cfg,
      chain: {
        state: async () => {
          throw new Error("rpc down");
        },
      },
      intents: { tokens: async () => list, quote: (async () => null) as never },
      rhea: { network: RHEA.testnet, holdings: async () => [] },
      poolReturn: pool,
    }).quote({ from: "NEAR", to: "USDC", amount: "0.5" });
    expect(q).toMatchObject({ amountOut: "1.049", caps: null, balance: null, executable: true });
  });

  it("refuses what isn't a trade", async () => {
    const q = make();
    await expect(q.quote({ from: "NEAR", to: "NEAR", amount: "1" })).rejects.toThrow("two different tokens");
    await expect(q.quote({ from: "NEAR", to: "USDC", amount: "0" })).rejects.toThrow("amount");
    await expect(q.quote({ from: "NEAR", to: "USDC", amount: "abc" })).rejects.toThrow("amount");
    await expect(q.quote({ from: "NEAR", to: "FAKECOIN", amount: "1" })).rejects.toThrow("Token check failed");
    const down = make({
      quote: async () => {
        throw new Error("down");
      },
    });
    await expect(down.quote({ from: "NEAR", to: "SOL", amount: "1" })).rejects.toThrow("couldn't quote");
  });

  it("on mainnet, NEAR into a listed token is executable under the dollar cap only", async () => {
    const small = await make({
      network: "mainnet",
      quote: async () => ({ amountInFormatted: "0.05", amountInUsd: "0.10", amountOutFormatted: "0.001", amountOutUsd: "0.0999", timeEstimate: 30 }),
    }).quote({ from: "NEAR", to: "SOL", amount: "0.05" });
    expect(small).toMatchObject({ route: { venue: "NEAR Intents" }, executable: true, minReceived: "0.00099" });
    const big = await make({ network: "mainnet" }).quote({ from: "NEAR", to: "SOL", amount: "0.5" });
    expect(big).toMatchObject({ executable: false, reason: "On mainnet Keybots swaps at most $0.15; this is about $1.00." });
  });

  it("names the network and says where the token lands", async () => {
    const m = await make({ network: "mainnet" }).quote({ from: "NEAR", to: "SOL", amount: "0.05" });
    expect(m.network).toBe("NEAR mainnet");
    expect(m.lands).toMatch(/NEAR Intents balance/);
    const t = await make().quote({ from: "NEAR", to: "USDC", amount: "0.5" });
    expect(t.network).toBe("NEAR testnet");
    expect(t.lands).toBe("Lands in Spend Limits (leash.x.testnet).");
  });
});

describe("orders from the panel", () => {
  it("builds commands the watcher's rules read", () => {
    const stop = orderFor("stop", "NEAR", "USDC", "1", "1.5");
    expect(stop).toMatchObject({ symbol: "NEAR", direction: "below", command: "swap 1 near to usdc if near drops below 1.5" });
    expect(parse((stop as { command: string }).command)).toEqual({
      kind: "watch",
      command: "swap 1 near to usdc",
      trade: { amount: "1", from: "NEAR", to: "USDC" },
      symbol: "NEAR",
      direction: "below",
      price: "1.5",
    });
    const take = orderFor("take", "NEAR", "USDT", "0.5", "4") as { command: string };
    expect(parse(take.command)).toMatchObject({ kind: "watch", command: "swap 0.5 near to usdt", symbol: "NEAR", direction: "above", price: "4" });
    const limit = orderFor("limit", "USDT", "NEAR", "2", "1.8") as { command: string };
    expect(limit.command).toBe("swap 2 usdt to near if near drops below 1.8");
    expect(parse(limit.command)).toMatchObject({ kind: "watch", command: "swap 2 usdt to near", symbol: "NEAR", direction: "below", price: "1.8" });
    expect(orderFor("limit", "NEAR", "USDC", "1", "3")).toMatchObject({ symbol: "NEAR", direction: "above" });
    expect(orderFor("stop", "USDC", "NEAR", "1", "3")).toEqual({ problem: "A stop-loss sells a token at a price. Put that token in You pay." });
  });

  it("a stop-loss under the price is ready, with the current price and a plain line", async () => {
    const q = await make().quote({ from: "NEAR", to: "USDC", amount: "0.5", order: "stop", trigger: "1.50" });
    expect(q).toMatchObject({
      command: "swap 0.5 near to usdc if near drops below 1.5",
      order: { kind: "stop", symbol: "NEAR", direction: "below", trigger: "1.5", now: 2, line: "Sells 0.5 NEAR for USDC when NEAR is below $1.5." },
      problem: null,
      ready: true,
    });
  });

  it("an order that would run right away says so", async () => {
    const q = await make().quote({ from: "NEAR", to: "USDC", amount: "0.5", order: "stop", trigger: "2.5" });
    expect(q).toMatchObject({ ready: false, problem: "NEAR is already below $2.5 (now $2.00), so this would run right away. Use Swap." });
    const t = await make().quote({ from: "NEAR", to: "USDC", amount: "0.5", order: "take", trigger: "1" });
    expect(t.ready).toBe(false);
  });

  it("a limit buy with dollars watches the token being bought", async () => {
    const q = await make().quote({ from: "USDC", to: "NEAR", amount: "1", order: "limit", trigger: "1.8" });
    expect(q).toMatchObject({ order: { symbol: "NEAR", direction: "below", now: 2 }, command: "swap 1 usdc to near if near drops below 1.8", ready: true });
  });

  it("an order isn't held to today's cap or the balance now, only to the per-trade cap", async () => {
    const spent = { available: "0", agents: [{ account: cfg.agents.trade, agent: { ...trader, spent_today: (2n * NEAR24).toString() } }] };
    expect((await make({ state: spent }).quote({ from: "NEAR", to: "USDC", amount: "0.5", order: "stop", trigger: "1" })).ready).toBe(true);
    expect((await make().quote({ from: "NEAR", to: "USDC", amount: "1.5", order: "stop", trigger: "1" })).problem).toMatch(/per-trade limit/);
  });

  it("needs a trigger price", async () => {
    await expect(make().quote({ from: "NEAR", to: "USDC", amount: "0.5", order: "stop" })).rejects.toThrow("trigger");
  });
});

describe("the token picker", () => {
  it("lists what trades here first, with prices and the leash's balances", async () => {
    const { tokens } = await make().tokens();
    expect(tokens.map((t) => t.symbol)).toEqual(["NEAR", "USDT", "USDC", "SOL", "ETH"]);
    expect(tokens[0]).toEqual({ symbol: "NEAR", chain: "near", price: 2, balance: "1.2", tradable: true });
    expect(tokens.find((t) => t.symbol === "USDC")).toMatchObject({ balance: "3.5", tradable: true });
    expect(tokens.find((t) => t.symbol === "SOL")).toEqual({ symbol: "SOL", chain: "sol", price: 100, balance: null, tradable: false });
    expect((await make().tokens(2)).tokens).toHaveLength(2);
  });
});

describe("the routes", () => {
  const app = () =>
    buildApp({
      cfg: { ...loadConfig({}), ...cfg, apiToken: "" },
      chain: { state: async () => state(), tokenCap: async () => null } as never,
      receipts: { add() {}, list: () => [], paidBefore: () => false },
      intents: { tokens: async () => list, quote: async () => null, pick: async () => ({}) } as never,
      rhea: { network: RHEA.testnet, route: () => undefined, holdings: async () => [] } as never,
      poolReturn: pool,
    });

  it("GET /v1/quote", async () => {
    const r = await app().inject({ url: "/v1/quote?from=NEAR&to=USDC&amount=0.5" });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ amountOut: "1.049", command: "swap 0.5 near to usdc", ready: true });
    const o = await app().inject({ url: "/v1/quote?from=NEAR&to=USDC&amount=0.5&order=stop&trigger=1.5" });
    expect(o.json()).toMatchObject({ order: { kind: "stop" } });
  });

  it("answers 400 for a bad ask and 404 for a token NEAR Intents doesn't list", async () => {
    expect((await app().inject({ url: "/v1/quote?from=NEAR&to=USDC" })).statusCode).toBe(400);
    expect((await app().inject({ url: "/v1/quote?from=NEAR&to=USDC&amount=1&order=twap&trigger=1" })).statusCode).toBe(400);
    const r = await app().inject({ url: "/v1/quote?from=NEAR&to=NOPE&amount=1" });
    expect(r.statusCode).toBe(404);
    expect(r.json().error).toMatch(/Token check failed/);
  });

  it("GET /v1/tokens/list, and /v1/tokens is unchanged", async () => {
    const r = await app().inject({ url: "/v1/tokens/list" });
    expect(r.json().tokens[0]).toMatchObject({ symbol: "NEAR", balance: "1.2" });
    expect((await app().inject({ url: "/v1/tokens" })).json().symbols).toContain("NEAR");
  });
});
