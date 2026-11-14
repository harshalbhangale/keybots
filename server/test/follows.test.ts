import { describe, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildApp, followsFor, type Deps } from "../src/app.js";
import { runCommand } from "../src/agent.js";
import { loadConfig } from "../src/config.js";
import { fileFollows, memoryFollows, missesInRow, parseFollow, type FollowStore } from "../src/follows.js";
import { fakeKall, kallClient, type KallCall } from "../src/kall.js";
import type { Chain, Decision } from "../src/near.js";
import { memoryStore } from "../src/receipts.js";
import { RHEA } from "../src/rhea.js";

const NOW = Date.now();
const sec = (ms: number) => Math.floor(ms / 1000);
const HOUR = 3_600_000;

/** A call Kall recorded, `ago` ms before now; open for a day. */
const call = (postId: string, ago: number, more: Partial<KallCall> = {}): KallCall => ({
  postId,
  asset: "ETH",
  direction: "up",
  status: "open",
  returnBps: null,
  postedAt: sec(NOW - ago),
  expiresAt: sec(NOW - ago) + 86_400,
  text: null,
  ...more,
});

// NEAR is $4, so $1 is 0.25 NEAR. Testnet has no ETH: the trade swaps NEAR to USDC on Rhea.
const wnear = { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: 4 };
const eth = { assetId: "nep141:eth.omft.near", symbol: "ETH", blockchain: "eth", decimals: 18, price: 1900 };
const usdc = { assetId: "nep141:usdc", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 };
const list = [wnear, eth, usdc];
const intents = {
  tokens: async () => list,
  pick: async (asked: string) => {
    const sym = asked.toUpperCase() === "NEAR" ? "WNEAR" : asked.toUpperCase();
    const t = list.find((x) => x.symbol.toUpperCase() === sym);
    return t ? { asked, verified: true, token: t, alsoOn: [], reason: "listed" } : { asked, verified: false, alsoOn: [], reason: `${asked} isn't on NEAR Intents' list` };
  },
  quote: async () => ({ dry: true as const, amountIn: "1", amountInFormatted: "0.25", amountInUsd: "1.00", amountOut: "1", amountOutFormatted: "0.0005", amountOutUsd: "1.00", timeEstimate: 10 }),
};
const rhea = { network: RHEA.testnet, route: (s: string) => RHEA.testnet!.routes[s.toUpperCase()], quote: async () => "1000000000000000000000000" };

/** The leash as a fake: the Trading Agent may spend `perTrade` NEAR a trade, 2 a day; Rhea fills every swap. */
function fakeChain(perTrade = "1000000000000000000000000") {
  const swaps: { agent: string; args: { amount: string; msg?: string } }[] = [];
  const paid: Decision = { status: "paid", rule: null, reason: "Within your rules", pending_id: null };
  const chain = {
    state: async () => ({
      owner: "x.testnet", leash: "leash.x.testnet", paused: false, available: "5", allowlist: [], blocklist: [], pending: [],
      agents: [{ account: "trader.x.testnet", agent: { tier: "trusted" as const, per_payment_cap: perTrade, daily_cap: "2000000000000000000000000", spent_today: "0", day: 0 } }],
    }),
    swap: async (agent: string, args: { amount: string; msg?: string }) => {
      swaps.push({ agent, args });
      const out = JSON.parse(args.msg!).actions[0].token_out as string;
      return { decision: paid, txHash: "AUTO", events: [{ event: "swapped" }], logs: [`Swapped ${args.amount} wrap.testnet for 1000000000000000000000000 ${out}, total fee 30`] };
    },
    txUrl: (h: string) => `https://testnet.nearblocks.io/txns/${h}`,
  } as unknown as Chain;
  return { chain, swaps };
}

const baseCfg = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: { apiKey: "", model: "m", base: "b" }, aiFallback: "off" as const };

/** A follow of @CryptoKaleo added an hour ago, Kall with `calls` for them, and the poller with the auto-trading switch set. */
function setup(opts: { calls?: KallCall[]; autoTrade?: boolean; perTrade?: string; follows?: FollowStore } = {}) {
  const follows = opts.follows ?? memoryFollows();
  const kall = fakeKall({
    callers: [{ handle: "cryptokaleo", focus: "BTC and high-conviction alts", tracked: true, open: 1, settled: 4, hits: 1, medianBps: -120 }],
    calls: { cryptokaleo: opts.calls ?? [] },
  });
  const { chain, swaps } = fakeChain(opts.perTrade);
  const receipts = memoryStore();
  const deps: Deps = { cfg: { ...baseCfg, autoTrade: opts.autoTrade ?? true }, chain, receipts, intents: intents as never, rhea: rhea as never, follows, kall };
  return { deps, follows, kall, swaps, receipts, poller: followsFor(deps) };
}
const follow = (follows: FollowStore, rules = {}) => follows.upsert("@CryptoKaleo", rules, NOW - HOUR);

describe("following a KOL: the rules", () => {
  it("never trades a call from before you followed, and never the same call twice", async () => {
    const s = setup({ calls: [call("new", 10 * 60_000), call("old", 2 * HOUR)] });
    follow(s.follows);
    const trades = await s.poller.poll("cryptokaleo");
    expect(trades.map((t) => t.postId)).toEqual(["new"]);
    expect(trades[0]).toMatchObject({ status: "traded", handle: "CryptoKaleo", postUrl: "https://x.com/CryptoKaleo/status/new", onRequest: false });
    expect(await s.poller.poll("cryptokaleo")).toEqual([]);
    expect(s.swaps).toHaveLength(1);
    expect(s.follows.get("cryptokaleo")).toMatchObject({ lastSeenPostId: "new", spentTodayUsd: 1 });
  });

  it("skips a sell when you follow buys only, and a sell of a token you don't hold even with both", async () => {
    const s = setup({ calls: [call("down", 60_000, { direction: "down" })] });
    follow(s.follows);
    expect((await s.poller.poll("cryptokaleo"))[0]).toMatchObject({ status: "skipped", side: "sell", message: "Skipped: ETH call from @CryptoKaleo is a sell, you follow buys only" });

    const b = setup({ calls: [call("eth-down", 60_000, { direction: "down" }), call("near-down", 30_000, { direction: "down", asset: "NEAR" })] });
    follow(b.follows, { sides: "both" });
    const [ethDown, nearDown] = await b.poller.poll("cryptokaleo");
    expect(ethDown).toMatchObject({ status: "skipped", message: "Skipped: ETH call from @CryptoKaleo, you hold no ETH to sell" });
    expect(nearDown).toMatchObject({ status: "traded", side: "sell", message: "Sold $1 of NEAR for USDC for you" });
  });

  it("sizes each trade to your dollars per call, and stops at your dollars a day", async () => {
    const s = setup({ calls: [call("a", 30 * 60_000), call("b", 20 * 60_000)] });
    follow(s.follows, { perCallUsd: 2, perDayUsd: 3 });
    const [a, b] = await s.poller.poll("cryptokaleo");
    expect(a).toMatchObject({ status: "traded", usd: 2, message: "Bought $2 of ETH for you (testnet: NEAR → USDC)" });
    expect(b).toMatchObject({ status: "skipped", message: "Skipped: over your $3 a day for @CryptoKaleo" });
    // $2 at $4 a NEAR is 0.5 NEAR.
    expect(s.swaps[0]!.args.amount).toBe("500000000000000000000000");
  });

  it("stops after N misses in a row, counting only calls since you followed", async () => {
    const misses = [1, 2, 3].map((i) => call(`m${i}`, (40 - i) * 60_000, { status: "miss", returnBps: -200, expiresAt: sec(NOW - 60_000) }));
    const before = [4, 5, 6].map((i) => call(`old${i}`, (2 + i) * HOUR, { status: "miss" }));
    expect(missesInRow([...misses, ...before], sec(NOW - HOUR))).toBe(3);

    const s = setup({ calls: [call("fresh", 60_000), ...misses, ...before] });
    follow(s.follows);
    const trades = await s.poller.poll("cryptokaleo");
    expect(s.follows.get("cryptokaleo")!.pausedReason).toMatch(/missed 3 calls in a row/);
    expect(trades.every((t) => t.status === "skipped")).toBe(true);
    expect(s.swaps).toHaveLength(0);
    // Paused: the minute's poll leaves them alone until auto is turned back on.
    expect(await s.poller.pollAll()).toEqual([]);
    expect(s.follows.upsert("CryptoKaleo", { auto: true })).toMatchObject({ pausedReason: null, missesInRow: 0 });
  });

  it("only ever counts misses since you followed", async () => {
    const s = setup({ calls: [call("fresh", 60_000), ...[4, 5, 6].map((i) => call(`old${i}`, (2 + i) * HOUR, { status: "miss" }))] });
    follow(s.follows);
    expect((await s.poller.poll("cryptokaleo"))[0]).toMatchObject({ status: "traded" });
  });

  it("skips a token NEAR Intents can't verify, a post that reads as unsure, and a call that already ended", async () => {
    const s = setup({
      calls: [
        call("fake", 30 * 60_000, { asset: "FAKECOIN" }),
        call("unsure", 20 * 60_000, { text: "$ETH buying here, or maybe dumping, bearish and bullish" }),
        call("ended", 50 * 60_000, { expiresAt: sec(NOW - 60_000) }),
      ],
    });
    follow(s.follows);
    const byPost = Object.fromEntries((await s.poller.poll("cryptokaleo")).map((t) => [t.postId, t]));
    expect(byPost.fake).toMatchObject({ status: "skipped", message: "Skipped: FAKECOIN call from @CryptoKaleo, FAKECOIN isn't a token we could verify" });
    expect(byPost.unsure).toMatchObject({ status: "skipped", message: "Skipped: @CryptoKaleo's ETH post reads as unsure, and you follow sure calls only" });
    expect(byPost.ended).toMatchObject({ status: "skipped", message: "Skipped: @CryptoKaleo's ETH call had already ended" });
    expect(s.swaps).toHaveLength(0);
  });

  it("says when the Trading Agent's caps stop it, in plain words", async () => {
    const s = setup({ calls: [call("big", 60_000)], perTrade: "100000000000000000000000" });
    follow(s.follows);
    const [t] = await s.poller.poll("cryptokaleo");
    expect(t).toMatchObject({ status: "skipped", message: "Not traded: over your 0.1 NEAR per-trade limit" });
    expect(t!.receiptId).toBeTruthy();
    expect(s.swaps).toHaveLength(0);
  });

  it("no message uses jargon", async () => {
    const s = setup({ calls: [call("a", 60_000), call("b", 2 * 60_000, { direction: "down" }), call("c", 3 * 60_000, { asset: "FAKECOIN" })] });
    follow(s.follows);
    for (const t of await s.poller.poll("cryptokaleo")) expect(t.message).not.toMatch(/leash|R\d|Inbox Agent/);
  });
});

describe("following a KOL: the auto-trading switch", () => {
  it("off (the default): records what it would have done, and trades nothing", async () => {
    expect(loadConfig({}).autoTrade).toBe(false);
    const s = setup({ calls: [call("p1", 60_000)], autoTrade: false });
    follow(s.follows);
    const [t] = await s.poller.poll("cryptokaleo");
    expect(t).toMatchObject({
      status: "skipped",
      reason: "Auto-trading is off on this server",
      message: "Would have bought $1 of ETH for you (testnet: NEAR → USDC), but auto-trading is off on this server",
      receiptId: null,
    });
    expect(s.swaps).toHaveLength(0);
    expect(s.receipts.list()).toHaveLength(0);
  });

  it("on: the Trading Agent swaps through the leash, and the receipt names the KOL and the post", async () => {
    const s = setup({ calls: [call("2118378232730828998", 60_000)] });
    follow(s.follows);
    const [t] = await s.poller.poll("cryptokaleo");
    expect(t).toMatchObject({ status: "traded", side: "buy", asset: "ETH", usd: 1, reason: null, message: "Bought $1 of ETH for you (testnet: NEAR → USDC)", txUrl: "https://testnet.nearblocks.io/txns/AUTO" });
    expect(s.swaps[0]!.agent).toBe("trader.x.testnet");
    const [receipt] = s.receipts.list();
    expect(receipt!.id).toBe(t!.receiptId);
    expect(receipt!.outcome).toBe("swapped");
    expect(receipt!.input).toEqual({
      text: "swap $1 of near to usdc",
      source: "follow",
      handle: "CryptoKaleo",
      postUrl: "https://x.com/CryptoKaleo/status/2118378232730828998",
    });
  });
});

describe("a message you copy still never trades", () => {
  it("a pasted swap is blocked, a follow command only ever swaps, and clients can't send source follow", async () => {
    const s = setup();
    const pasted = await runCommand(s.deps, "swap $1 of near to usdc", "pasted");
    expect(pasted.outcome).toBe("blocked");
    expect(pasted.summary).toBe("Blocked: trades only run from what you type, never from a copied message");
    const pay = await runCommand(s.deps, "pay friend 1", "follow", { handle: "x", postUrl: "https://x.com/x/status/1" });
    expect(pay).toMatchObject({ outcome: "blocked", message: "Only a swap runs for a KOL you follow." });
    const r = await buildApp(s.deps).inject({ method: "POST", url: "/v1/command", payload: { text: "swap $1 of near to usdc", source: "follow" } });
    expect(r.statusCode).toBe(400);
    expect(s.swaps).toHaveLength(0);
  });
});

describe("/v1/follows and /v1/kols", () => {
  it("follows, lists, changes rules and unfollows", async () => {
    const s = setup({ calls: [call("h", 3 * HOUR, { status: "hit", returnBps: 120 }), call("m", 4 * HOUR, { status: "miss", returnBps: -80 }), call("o", 60_000)] });
    const app = buildApp(s.deps);
    expect((await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "not a handle!" } })).statusCode).toBe(400);
    expect((await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "x", perCallUsd: -1 } })).statusCode).toBe(400);
    expect((await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "x", sides: "sell" } })).statusCode).toBe(400);

    const added = await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "@CryptoKaleo" } });
    expect(added.statusCode).toBe(200);
    expect(added.json()).toMatchObject({
      handle: "CryptoKaleo", auto: true, perCallUsd: 1, perDayUsd: 3, sides: "buy", highOnly: true, stopAfterMisses: 3,
      spentTodayUsd: 0, lastCallAt: null, pausedReason: null,
      record: { hits: 1, misses: 1, open: 1, avgReturnBps: 20 },
    });

    const changed = await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "cryptokaleo", perCallUsd: 0.5, sides: "both" } });
    expect(changed.json()).toMatchObject({ handle: "cryptokaleo", perCallUsd: 0.5, perDayUsd: 3, sides: "both" });

    const listed = (await app.inject({ method: "GET", url: "/v1/follows" })).json();
    expect(listed.follows).toHaveLength(1);
    expect(listed.trades).toEqual([]);

    expect((await app.inject({ method: "DELETE", url: "/v1/follows/CRYPTOKALEO" })).json()).toEqual({ ok: true });
    expect((await app.inject({ method: "DELETE", url: "/v1/follows/cryptokaleo" })).statusCode).toBe(404);
  });

  it("check with latest takes their newest call even from before the follow, once", async () => {
    const s = setup({ calls: [call("2118378232730828998", 3 * HOUR, { status: "miss", returnBps: -207, expiresAt: sec(NOW - HOUR) })] });
    const app = buildApp(s.deps);
    await app.inject({ method: "POST", url: "/v1/follows", payload: { handle: "CryptoKaleo" } });
    // Without latest, an older call is left alone.
    expect((await app.inject({ method: "POST", url: "/v1/follows/cryptokaleo/check", payload: {} })).json()).toEqual({ trades: [] });

    const r = await app.inject({ method: "POST", url: "/v1/follows/cryptokaleo/check", payload: { latest: true } });
    const [t] = r.json().trades;
    expect(t).toMatchObject({ status: "traded", onRequest: true, postId: "2118378232730828998", message: "Bought $1 of ETH for you (testnet: NEAR → USDC)" });
    // Asked again: the same trade, not a second one.
    const again = (await app.inject({ method: "POST", url: "/v1/follows/cryptokaleo/check", payload: { latest: true } })).json().trades;
    expect(again[0].id).toBe(t.id);
    expect(s.swaps).toHaveLength(1);

    const listed = (await app.inject({ method: "GET", url: "/v1/follows" })).json();
    expect(listed.trades.map((x: { id: string }) => x.id)).toEqual([t.id]);
    expect(listed.follows[0]).toMatchObject({ spentTodayUsd: 1, lastCallAt: new Date(sec(NOW - 3 * HOUR) * 1000).toISOString() });
    expect((await app.inject({ method: "POST", url: "/v1/follows/nobody/check", payload: {} })).statusCode).toBe(404);
  });

  it("suggests Kall's tracked callers with their records", async () => {
    const s = setup();
    const r = (await buildApp(s.deps).inject({ method: "GET", url: "/v1/kols" })).json();
    expect(r).toEqual({ callers: [{ handle: "cryptokaleo", focus: "BTC and high-conviction alts", hits: 1, misses: 3, open: 1, avgReturnBps: -120 }] });
  });
});

describe("the follows store and the Kall client", () => {
  it("keeps follows and their trades on disk, and checks a follow body", () => {
    const dir = mkdtempSync(join(tmpdir(), "airkey-follows-"));
    try {
      fileFollows(dir).upsert("CryptoKaleo", { perDayUsd: 5 });
      expect(fileFollows(dir).get("cryptokaleo")).toMatchObject({ handle: "CryptoKaleo", perDayUsd: 5, perCallUsd: 1 });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
    expect(parseFollow({ handle: "@a_b", stopAfterMisses: 0, highOnly: false })).toEqual({ handle: "a_b", rules: { stopAfterMisses: 0, highOnly: false } });
    expect(parseFollow({ handle: "sixteen_chars_xx" })).toHaveProperty("error");
  });

  it("reads Kall's shapes, one call per post, and caches a minute", async () => {
    let asked = 0;
    const body = {
      calls: [
        { key: "0x1", postId: "9", asset: "eth", direction: "up", status: "miss", returnBps: -207, postedAt: 100, expiresAt: 200 },
        { key: "0x2", postId: "9", asset: "eth", direction: "up", status: "miss", returnBps: -207, postedAt: 100, expiresAt: 200 },
        { key: "0x3", postId: "8", asset: "BTC", direction: "up", status: "hit", returnBps: 12, postedAt: 90, expiresAt: 190 },
      ],
      trades: [],
      writer: "0x0",
      deleted: 0,
    };
    const fetcher = (async (url: string) => {
      asked++;
      expect(url).toBe("https://kall.test/api/callers/cryptokaleo");
      return new Response(JSON.stringify(body));
    }) as unknown as typeof fetch;
    const kall = kallClient("https://kall.test/", fetcher);
    const calls = await kall.caller("CryptoKaleo");
    expect(calls).toEqual([
      { postId: "9", asset: "ETH", direction: "up", status: "miss", returnBps: -207, postedAt: 100, expiresAt: 200, text: null },
      { postId: "8", asset: "BTC", direction: "up", status: "hit", returnBps: 12, postedAt: 90, expiresAt: 190, text: null },
    ]);
    await kall.caller("cryptokaleo");
    expect(asked).toBe(1);
  });
});
