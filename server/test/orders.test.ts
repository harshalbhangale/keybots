import { describe, expect, it } from "vitest";
import { runCommand } from "../src/agent.js";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { checkOrders, crossed, memoryOrders } from "../src/orders.js";
import { parse } from "../src/parse.js";
import { memoryStore } from "../src/receipts.js";
import type { Chain } from "../src/near.js";

describe("reading a price-triggered order", () => {
  it("reads the trade, the token to watch, the direction and the price", () => {
    expect(parse("sell 1 near if it drops below 2")).toEqual({
      kind: "watch",
      command: "sell 1 near",
      trade: { amount: "1", from: "NEAR", to: "USDC" },
      symbol: "NEAR",
      direction: "below",
      price: "2",
    });
    expect(parse("buy $2 of sol when it goes above $95.50")).toMatchObject({ kind: "watch", command: "buy $2 of sol", symbol: "SOL", direction: "above", price: "95.5" });
    expect(parse("swap 1 usdc to near once near is under 3")).toMatchObject({ kind: "watch", symbol: "NEAR", direction: "below", price: "3" });
  });

  it("is not an order without a trade in front", () => {
    expect(parse("call me if it drops below 2").kind).toBe("unknown");
    // A payment with a condition is not something the leash can wait on.
    expect(parse("pay harshal 1 if it drops below 2").kind).not.toBe("watch");
  });
});

describe("crossed", () => {
  it("fires at or past the line, in the right direction", () => {
    expect(crossed({ direction: "below", price: 2 }, 2.01)).toBe(false);
    expect(crossed({ direction: "below", price: 2 }, 2)).toBe(true);
    expect(crossed({ direction: "above", price: 4 }, 3.99)).toBe(false);
    expect(crossed({ direction: "above", price: 4 }, 4.2)).toBe(true);
  });
});

// A NEAR Intents stand-in whose NEAR price can be moved.
function market(start: number) {
  let near = start;
  const list = () => [
    { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: near },
    { assetId: "nep141:usdc.near", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 },
  ];
  const pick = async (asked: string) => {
    const sym = asked.toUpperCase() === "NEAR" ? "WNEAR" : asked.toUpperCase();
    const t = list().find((x) => x.symbol.toUpperCase() === sym);
    return t ? { asked, verified: true, token: t, alsoOn: [], reason: "listed" } : { asked, verified: false, alsoOn: [], reason: `${asked.toUpperCase()} isn't on NEAR Intents' list` };
  };
  const intents = {
    tokens: async () => list(),
    pick,
    price: async (s: string) => (await pick(s)).token?.price,
    quote: async () => ({ dry: true as const, amountIn: "1", amountInFormatted: "1", amountInUsd: String(near), amountOut: "1", amountOutFormatted: String(near), amountOutUsd: String(near), timeEstimate: 10 }),
  };
  return { intents, move: (to: number) => void (near = to) };
}

const cfg = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: { apiKey: "", model: "m", base: "b" } };
const chain = {
  state: async () => ({
    owner: "o", leash: "l", paused: false, available: "0", allowlist: [], blocklist: [], pending: [],
    agents: [{ account: "trade.x.testnet", agent: { tier: "trusted" as const, per_payment_cap: "1000000000000000000000000", daily_cap: "2000000000000000000000000", spent_today: "0", day: 0 } }],
  }),
} as unknown as Chain;

describe("a price-triggered order, start to finish", () => {
  it("is created from typed words, waits, and runs the trade when the price crosses", async () => {
    const m = market(3.4);
    const deps = { cfg, chain, receipts: memoryStore(), intents: m.intents as never, orders: memoryOrders() };

    const r = await runCommand(deps, "sell 1 near if it drops below 3", "typed");
    expect(r.outcome).toBe("watching");
    expect(r.message).toBe("Watching NEAR (now $3.4). When it's below $3: sell 1 near.");
    expect(r.agent?.account).toBe("trade.x.testnet");
    expect(deps.orders.list()).toHaveLength(1);

    const run = async (command: string) => (await runCommand(deps, command, "typed")).id;
    // Still above the line: nothing happens.
    expect(await checkOrders(deps.orders, m.intents.price, run)).toHaveLength(0);
    expect(deps.orders.list()[0].status).toBe("watching");

    m.move(2.9);
    const fired = await checkOrders(deps.orders, m.intents.price, run);
    expect(fired).toHaveLength(1);
    expect(fired[0]).toMatchObject({ status: "triggered", triggeredPrice: 2.9 });
    // The trade ran through the same path as a typed command and left a receipt.
    const receipt = deps.receipts.list().find((x) => x.id === fired[0].receiptId);
    expect(receipt?.input.text).toBe("sell 1 near");
    expect(receipt?.outcome).toBe("quoted");

    // It never runs twice.
    expect(await checkOrders(deps.orders, m.intents.price, run)).toHaveLength(0);
  });

  it("is refused from pasted text, and for a token that isn't listed", async () => {
    const m = market(3.4);
    const deps = { cfg, chain, receipts: memoryStore(), intents: m.intents as never, orders: memoryOrders() };
    const pasted = await runCommand(deps, "sell 1 near if it drops below 3", "pasted");
    expect(pasted.outcome).toBe("blocked");
    expect(pasted.message).toMatch(/Orders only come from what you type/);
    const fake = await runCommand(deps, "sell 1 toshi if it drops below 3", "typed");
    expect(fake.outcome).toBe("blocked");
    expect(fake.message).toMatch(/Token check failed/);
    expect(deps.orders.list()).toHaveLength(0);
  });
});

describe("order routes", () => {
  it("lists orders and cancels one that is still waiting, once", async () => {
    const m = market(3.4);
    const deps = { cfg, chain, receipts: memoryStore(), intents: m.intents as never, orders: memoryOrders() };
    const app = buildApp(deps);
    await runCommand(deps, "buy $2 of near if it drops below 3", "typed");

    const listed = (await app.inject("/v1/orders")).json().orders;
    expect(listed).toHaveLength(1);
    expect(listed[0]).toMatchObject({ symbol: "NEAR", direction: "below", price: 3, status: "watching", command: "buy $2 of near" });

    const cancelled = await app.inject({ method: "DELETE", url: `/v1/orders/${listed[0].id}` });
    expect(cancelled.json().status).toBe("cancelled");
    expect((await app.inject({ method: "DELETE", url: `/v1/orders/${listed[0].id}` })).statusCode).toBe(409);
    expect((await app.inject({ method: "DELETE", url: "/v1/orders/nope" })).statusCode).toBe(404);

    // A cancelled order is not watched any more.
    m.move(1);
    expect(await checkOrders(deps.orders, m.intents.price, async () => "x")).toHaveLength(0);
  });
});
