// The KOL call flow, offline: a fake Kall, a fake NEAR Intents, a fake Rhea and
// a fake leash that runs the contract's R1, R4 and R5 the way lib.rs does.
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { fakeKall, type KallClient } from "../src/kall.js";
import type { Chain, Decision } from "../src/near.js";
import { memoryStore } from "../src/receipts.js";
import { RHEA } from "../src/rhea.js";
import { SAMPLE_NOTE } from "../src/trade.js";

const NOW = Date.UTC(2026, 10, 14, 8, 15);
const DAY = Math.floor(NOW / 86_400_000);
const NEAR = 10n ** 24n;
const cfg = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: { apiKey: "", model: "m", base: "b" }, openAi: { apiKey: "", model: "m", base: "b" } };

// NEAR is $2 here: $1 is 0.5 NEAR, $3 is 1.5 NEAR (over the Trading Agent's 1 NEAR a trade).
const tokens = [
  { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: 2 },
  { assetId: "nep141:usdc", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 },
  { assetId: "nep141:sol.omft.near", symbol: "SOL", blockchain: "sol", decimals: 9, price: 80 },
  { assetId: "nep141:eth.omft.near", symbol: "ETH", blockchain: "eth", decimals: 18, price: 3000 },
];
const intents = {
  tokens: async () => tokens,
  price: async (s: string) => tokens.find((t) => t.symbol === s.toUpperCase())?.price,
  pick: async (asked: string) => {
    const sym = asked.toUpperCase() === "NEAR" ? "WNEAR" : asked.toUpperCase();
    const t = tokens.find((x) => x.symbol.toUpperCase() === sym);
    return t ? { asked, verified: true, token: t, alsoOn: [], reason: "listed" } : { asked, verified: false, alsoOn: [], reason: `${asked} isn't on NEAR Intents' list` };
  },
  quote: async (from: { price?: number }, to: { price?: number }, amount: string) => {
    const usd = Number(amount) * (from.price ?? 0);
    return { dry: true as const, amountIn: amount, amountInFormatted: amount, amountInUsd: usd.toFixed(2), amountOut: "1", amountOutFormatted: String(usd / (to.price ?? 1)), amountOutUsd: usd.toFixed(2), timeEstimate: 10 };
  },
};

/** Rhea pays 2 USDC per NEAR (24 decimals on testnet). */
const makeRhea = () => ({
  network: RHEA.testnet as (typeof RHEA)["testnet"] | undefined,
  route: (s: string) => RHEA.testnet!.routes[s.toUpperCase()],
  quote: async (_r: unknown, amountIn: string) => (BigInt(amountIn) * 2n).toString(),
  holdings: async () => [],
});

/** The leash: the Trading Agent may spend 1 NEAR a trade, 2 a day. Refusals come back as a successful tx with a `blocked` event. */
function fakeLeash(opts: { paused?: boolean; spent?: bigint; slow?: boolean; fills?: boolean; throws?: boolean } = {}) {
  const sent: Record<string, unknown>[] = [];
  const agent = { tier: "trusted" as const, per_payment_cap: String(NEAR), daily_cap: String(2n * NEAR), spent_today: String(opts.spent ?? 0n), day: DAY };
  const chain: Chain = {
    state: async () => ({ owner: "x.testnet", leash: "leash.x.testnet", paused: !!opts.paused, available: String(5n * NEAR), agents: [{ account: "trader.x.testnet", agent }], allowlist: [], blocklist: [], pending: [] }),
    isAllowed: async () => false,
    blockedReason: async () => null,
    facts: async () => ({ exists: true, isContract: false, createdAtNs: null }),
    pay: async () => {
      throw new Error("no payments here");
    },
    swap: async (_agent, args) => {
      sent.push(args);
      if (opts.throws) throw new Error("RPC timed out");
      if (opts.slow) await new Promise((r) => setTimeout(r, 50));
      const amount = BigInt(args.amount);
      const no = (rule: string, reason: string) => {
        const decision: Decision = { status: "blocked", rule, reason, pending_id: null };
        return { decision, txHash: "BLOCKEDTX", events: [{ standard: "airkey", event: "blocked", data: [{ rule, reason, swap: true }] }], logs: [] };
      };
      if (opts.paused) return no("R1", "Kill switch is on");
      if (amount > BigInt(agent.per_payment_cap)) return no("R4", "Over the per-payment cap of 1 NEAR");
      if (BigInt(agent.spent_today) + amount > BigInt(agent.daily_cap)) return no("R5", "Over the daily cap of 2 NEAR (1.8 NEAR spent today)");
      const decision: Decision = { status: "paid", rule: null, reason: "Within your rules", pending_id: null };
      if (opts.fills === false) return { decision, txHash: "SWAPTX", events: [{ event: "swap_failed" }], logs: [] };
      const msg = JSON.parse(String(args.msg));
      return { decision, txHash: "SWAPTX", events: [{ event: "swap" }], logs: [`Swapped ${args.amount} wrap.testnet for ${msg.actions[0].min_amount_out} usdc.itachicara.testnet, total fee 30`] };
    },
    swapToken: async () => {
      throw new Error("no sells here");
    },
    tokenCap: async () => null,
    txUrl: (h) => `https://testnet.nearblocks.io/txns/${h}`,
  };
  return { chain, sent };
}

const kall = () =>
  fakeKall({
    callers: [{ handle: "solcaller", focus: null, tracked: true, open: 1, settled: 5, hits: 3, medianBps: 40 }],
    calls: {
      solcaller: [
        { postId: "111", asset: "SOL", direction: "up", status: "open", returnBps: null, postedAt: NOW / 1000 - 600, expiresAt: null, text: "$SOL looks strong, buying here" },
        { postId: "222", asset: "ETH", direction: "up", status: "open", returnBps: null, postedAt: NOW / 1000 - 60, expiresAt: null, text: "$ETH long 10x, send it" },
        { postId: "333", asset: "NEAR", direction: "down", status: "hit", returnBps: 20, postedAt: NOW / 1000 - 1200, expiresAt: null, text: "Selling my $NEAR, top is in" },
      ],
    },
  });
const downKall: KallClient = { feed: async () => Promise.reject(new Error("down")), caller: async () => [] };

function setup(opts: Parameters<typeof fakeLeash>[0] & { kall?: KallClient } = {}) {
  const { chain, sent } = fakeLeash(opts);
  const clock = { t: NOW };
  const rhea = makeRhea();
  const receipts = memoryStore();
  const app = buildApp({ cfg, chain, receipts, intents: intents as never, rhea: rhea as never, kall: opts.kall ?? kall(), now: () => clock.t });
  const review = async (body: object) => app.inject({ method: "POST", url: "/v1/trade/review", payload: body });
  const confirm = async (reviewId: string) => app.inject({ method: "POST", url: "/v1/trade/confirm", payload: { reviewId } });
  return { app, sent, clock, rhea, receipts, review, confirm };
}

describe("GET /v1/kol/feed", () => {
  it("lists Kall's spot calls newest first, without perps, with the caller's record", async () => {
    const { app } = setup();
    const r = (await app.inject("/v1/kol/feed")).json();
    expect(r.source).toBe("kall");
    expect(r.note).toMatch(/Not every post on X/);
    expect(r.calls.map((c: { id: string }) => c.id)).toEqual(["kall-111", "kall-333"]);
    expect(r.calls[0]).toEqual({
      id: "kall-111",
      author: { handle: "solcaller", name: null },
      postedAt: new Date(NOW - 600_000).toISOString(),
      url: "https://x.com/solcaller/status/111",
      text: "$SOL looks strong, buying here",
      asset: "SOL",
      direction: "buy",
      record: { hits: 3, misses: 2 },
    });
    expect(r.calls[1].direction).toBe("sell");
  });

  it("falls back to three labelled samples when Kall doesn't answer or has nothing", async () => {
    for (const k of [downKall, fakeKall({})]) {
      const r = (await setup({ kall: k }).app.inject("/v1/kol/feed")).json();
      expect(r.source).toBe("sample");
      expect(r.note).toBe(SAMPLE_NOTE);
      expect(r.calls).toHaveLength(3);
      expect(r.calls.every((c: { author: { name: string }; url: null }) => c.author.name === "Sample post" && c.url === null)).toBe(true);
    }
  });
});

describe("POST /v1/trade/review", () => {
  it("shows Rhea's own numbers, the floor, the stand-in and the limits, and sends nothing", async () => {
    const { review, sent } = setup();
    const res = await review({ callId: "kall-111" });
    expect(res.statusCode).toBe(200);
    const r = res.json();
    expect(r.expiresAt).toBe(new Date(NOW + 30_000).toISOString());
    expect(r.call).toEqual({ author: { handle: "solcaller", name: null }, postedAt: new Date(NOW - 600_000).toISOString(), url: "https://x.com/solcaller/status/111", text: "$SOL looks strong, buying here", asset: "SOL", direction: "buy" });
    expect(r.reading).toEqual({ by: "rules", detail: "Read on the Keybots server by fixed rules, not by AI" });
    expect(r.trade).toEqual({
      network: "NEAR testnet",
      venue: "Rhea, pool 1103",
      pay: { amount: "0.5", symbol: "NEAR" },
      // 0.5 NEAR at 2 USDC a NEAR; the leash takes no less than 1% under it.
      receive: { amount: "1", symbol: "USDC", min: "0.99" },
      slippagePct: 1,
      fundsSit: "In Spend Limits, leash.x.testnet. The tokens come back to it.",
      standIn: "The post is about SOL. Testnet has no SOL, so this swaps NEAR to USDC instead.",
    });
    expect(r.mainnetQuote).toEqual({ label: "NEAR Intents quote (mainnet, dry: no funds move)", payAmount: "0.5", receiveAmount: "0.0125", symbol: "SOL" });
    expect(r.limits).toEqual({
      agent: "trader.x.testnet",
      agentName: "Trading Agent",
      perTrade: "1",
      daily: "2",
      spentToday: "0",
      stopped: false,
      within: true,
      sentence: "The Trading Agent can spend up to 1 NEAR a trade and 2 NEAR a day. You can stop it.",
      willRefuse: null,
      refusedBy: null,
    });
    expect(r.ttlSeconds).toBe(30);
    expect(sent).toHaveLength(0);
  });

  it("a sell of NEAR has no stand-in; copied text has no author", async () => {
    const r = (await setup().review({ text: "Selling my $NEAR here, top is in" })).json();
    expect(r.call).toMatchObject({ author: null, postedAt: null, url: null, asset: "NEAR", direction: "sell" });
    expect(r.trade.standIn).toBeNull();
  });

  it("says when the contract will refuse it", async () => {
    expect((await setup().review({ callId: "kall-111", usd: 3 })).json().limits).toMatchObject({ within: false, willRefuse: "Over the 1 NEAR per-trade limit: the contract will refuse it." });
    expect((await setup({ spent: 1800n * 10n ** 21n }).review({ callId: "kall-111" })).json().limits.willRefuse).toBe("Over the 2 NEAR daily limit (1.8 NEAR spent today): the contract will refuse it.");
    expect((await setup({ paused: true }).review({ callId: "kall-111" })).json().limits).toMatchObject({ stopped: true, willRefuse: "Stop everything is on: Keybots won't send it.", refusedBy: "server" });
    expect((await setup().review({ callId: "kall-111", usd: 3 })).json().limits.refusedBy).toBe("contract");
  });

  it("while one reviewed trade is sending, a second review can't be confirmed", async () => {
    const { review, confirm, sent } = setup({ slow: true });
    const first = (await review({ callId: "kall-111" })).json().reviewId;
    const second = (await review({ callId: "kall-111" })).json().reviewId;
    const [a, b] = await Promise.all([confirm(first), confirm(second)]);
    expect(a.statusCode).toBe(200);
    expect(b.statusCode).toBe(409);
    expect(b.json()).toEqual({ error: "Another trade is still being sent. Wait for its result." });
    expect(sent).toHaveLength(1);
  });

  it("when NEAR doesn't answer, the result is unknown, never 'failed', and it isn't retried", async () => {
    const { review, confirm, sent } = setup({ throws: true });
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const r = (await confirm(reviewId)).json();
    expect(r).toMatchObject({ status: "unknown", receipt: { receive: null, tx: null } });
    expect(r.receipt.summary).toContain("can't say if it went through");
    expect((await confirm(reviewId)).json()).toMatchObject({ status: "unknown", repeat: true });
    expect(sent).toHaveLength(1);
  });

  it("refuses in plain words what it can't trade", async () => {
    const { review } = setup();
    const cases: [object, number, RegExp][] = [
      [{ text: "good morning everyone" }, 422, /isn't a trade call/],
      [{ text: "$ETH long 10x, send it" }, 422, /perp call on ETH/],
      [{ text: "$SOL is weak, selling" }, 422, /doesn't short/],
      [{ text: "$TOSHI2 to the moon, buying" }, 422, /Token check failed/],
      [{ text: "$NEAR breakout, buying" }, 422, /buy NEAR/],
      [{ callId: "kall-999" }, 404, /isn't in the feed/],
      [{ callId: "kall-111", usd: 11 }, 400, /up to 10/],
      [{}, 400, /callId/],
    ];
    for (const [body, code, msg] of cases) {
      const r = await review(body);
      expect(r.statusCode, JSON.stringify(body)).toBe(code);
      expect(r.json().error).toMatch(msg);
      expect(r.json().error).not.toMatch(/R\d/);
    }
  });
});

describe("POST /v1/trade/confirm", () => {
  it("swaps once through the Trading Agent and reports what the chain filled", async () => {
    const { review, confirm, sent, receipts } = setup();
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const res = await confirm(reviewId);
    expect(res.statusCode).toBe(200);
    const r = res.json();
    expect(r.status).toBe("swapped");
    expect(r.receipt).toMatchObject({
      by: "contract",
      rule: null,
      reason: null,
      agent: "trader.x.testnet",
      pay: { amount: "0.5", symbol: "NEAR" },
      receive: { amount: "0.99", symbol: "USDC" },
      venue: "Rhea, pool 1103",
      standIn: "The post is about SOL. Testnet has no SOL, so this swaps NEAR to USDC instead.",
      tx: { hash: "SWAPTX", url: "https://testnet.nearblocks.io/txns/SWAPTX" },
      post: { url: "https://x.com/solcaller/status/111", author: "solcaller" },
    });
    expect(r.receipt.summary).toBe("Swapped 0.5 NEAR for 0.99 USDC");
    expect(sent).toHaveLength(1);
    // Never below what the review showed.
    expect(JSON.parse(String(sent[0]!.msg)).actions[0].min_amount_out).toBe(String((NEAR / 2n) * 2n * 99n / 100n));
    expect(receipts.list(1)[0]!.input).toMatchObject({ source: "reviewed-call", handle: "solcaller", postUrl: "https://x.com/solcaller/status/111" });
  });

  it("a repeat confirm gets the same receipt and the chain sees one call", async () => {
    const { review, confirm, sent } = setup();
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const first = (await confirm(reviewId)).json();
    const again = await confirm(reviewId);
    expect(again.statusCode).toBe(200);
    expect(again.json()).toEqual({ ...first, repeat: true });
    expect(sent).toHaveLength(1);
  });

  it("a confirm while the same review is sending gets 409", async () => {
    const { review, confirm, sent } = setup({ slow: true });
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const [a, b] = await Promise.all([confirm(reviewId), confirm(reviewId)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect((a.statusCode === 409 ? a : b).json()).toEqual({ error: "Already sending this trade." });
    expect(sent).toHaveLength(1);
  });

  it("a review more than 30 seconds old is refused and nothing is sent", async () => {
    const { review, confirm, clock, sent } = setup();
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    clock.t += 30_001;
    const r = await confirm(reviewId);
    expect(r.statusCode).toBe(409);
    expect(r.json()).toEqual({ error: "This quote is more than 30 seconds old. Review it again.", expired: true });
    expect(sent).toHaveLength(0);
    expect((await confirm("nope")).statusCode).toBe(404);
  });

  it("over a limit, the contract decides: the leash refuses it on chain and says which rule", async () => {
    const { review, confirm, sent } = setup();
    const { reviewId } = (await review({ callId: "kall-111", usd: 3 })).json();
    const r = (await confirm(reviewId)).json();
    expect(sent).toHaveLength(1);
    expect(r.status).toBe("blocked");
    expect(r.receipt).toMatchObject({ by: "contract", rule: "R4", reason: "Over the per-payment cap of 1 NEAR", receive: null, tx: { hash: "BLOCKEDTX" } });
    expect(r.receipt.summary).toBe("Blocked: over your 1 NEAR per-trade limit");
  });

  it("over today's limit, the same: R5 from the contract", async () => {
    const { review, confirm, sent } = setup({ spent: 1800n * 10n ** 21n });
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const r = (await confirm(reviewId)).json();
    expect(sent).toHaveLength(1);
    expect(r).toMatchObject({ status: "blocked", receipt: { by: "contract", rule: "R5" } });
    expect(r.receipt.summary).toBe("Blocked: over your 2 NEAR daily limit");
  });

  it("Stop everything is refused here, and says so", async () => {
    const { review, confirm, sent } = setup({ paused: true });
    const { reviewId } = (await review({ callId: "kall-111" })).json();
    const r = (await confirm(reviewId)).json();
    expect(sent).toHaveLength(0);
    expect(r).toMatchObject({ status: "blocked", receipt: { by: "server", rule: null, tx: null, receive: null } });
    expect(r.receipt.summary).toBe("Blocked: you turned on Stop everything");
  });

  it("a quote or an unfilled swap is never shown as swapped", async () => {
    // Rhea didn't fill: the tx went through, nothing came back.
    const unfilled = setup({ fills: false });
    const a = (await unfilled.confirm((await unfilled.review({ callId: "kall-111" })).json().reviewId)).json();
    expect(a).toMatchObject({ status: "failed", receipt: { receive: null } });
    // No venue by the time it runs: the agent only quotes it.
    const quoted = setup();
    const { reviewId } = (await quoted.review({ callId: "kall-111" })).json();
    quoted.rhea.network = undefined;
    const b = (await quoted.confirm(reviewId)).json();
    expect(b).toMatchObject({ status: "failed", receipt: { receive: null, tx: null } });
    expect(quoted.sent).toHaveLength(0);
  });

  it("pasted text still can't trade without a review", async () => {
    const { app, sent } = setup();
    const pasted = (await app.inject({ method: "POST", url: "/v1/command", payload: { text: "swap 0.5 near to usdc", source: "pasted" } })).json();
    expect(pasted.outcome).toBe("blocked");
    expect(pasted.summary).toBe("Blocked: trades only run from what you type, never from a copied message");
    const sneaky = await app.inject({ method: "POST", url: "/v1/command", payload: { text: "swap 0.5 near to usdc", source: "reviewed-call" } });
    expect(sneaky.statusCode).toBe(400);
    expect(sent).toHaveLength(0);
  });
});
