// A KOL's call, start to finish: the feed (the X feed's tracked calls, calls from a
// Telegram group the bot is in, or labelled samples) -> a review with the exact numbers (nothing sent) -> a confirm
// within 30 seconds -> the Trading Agent asks the leash, the contract decides
// -> a receipt from what the chain said.
//
// A review is read by fixed rules (calls.ts), never by AI. A confirmed review
// runs once: a second confirm gets the same receipt back, never a second
// transaction. Over a limit, the trade still goes to the leash so the contract
// refuses it on chain; only Stop everything is refused here first.
import { randomUUID } from "node:crypto";
import { runCommand, tidy, type Deps as CommandDeps, type FollowSource } from "./agent.js";
import { namesContract, readCall, routeCall, type Call } from "./calls.js";
import { postUrl } from "./follows.js";
import type { XFeedClient } from "./xfeed.js";
import { toYocto } from "./parse.js";
import { fromUnits, minOut } from "./rhea.js";
import type { Receipt } from "./receipts.js";
import { readSignal, type Signal, type TelegramSource, type TgCall } from "./telegram.js";

export interface FeedCall {
  id: string;
  author: { handle: string; name: string | null };
  postedAt: string;
  /** Where it was posted: "x" is X; "telegram" is a group the bot is in. */
  source: "x" | "telegram" | "sample";
  /** The post on X or the t.me link; null for a sample or a private Telegram group. */
  url: string | null;
  text: string | null;
  asset: string;
  direction: "buy" | "sell";
  record: { hits: number; misses: number } | null;
  /** A leveraged signal read as spot: what it said, and the line the card shows. */
  signal?: Signal & { note: string };
}

/**
 * A copied or pasted post, by the fixed rules: a spot call as it is, or a
 * leveraged signal ("TAO LONG 10x") read as spot, with what it said.
 */
export function readPosted(text: string): { call: Call; signal?: Signal & { note: string } } {
  const call = readCall(text);
  if ((call.isCall && call.asset && call.direction && call.instrument === "spot") || namesContract(text)) return { call };
  const sig = readSignal(text);
  if (!sig) return { call };
  return {
    call: {
      isCall: true,
      confidence: "high",
      asset: sig.asset,
      direction: sig.direction === "buy" ? "bullish" : "bearish",
      instrument: "spot",
      leverage: null,
      summary: `${sig.direction === "buy" ? "Bullish" : "Bearish"} signal on ${sig.asset}, read as spot.`,
    },
    signal: { ...sig.signal, note: signalNote(sig.direction, sig.signal.leverage) },
  };
}

/** "Leveraged call (10x): Keybots buys spot, no leverage." */
export function signalNote(direction: "buy" | "sell", leverage: string | null): string {
  return `Leveraged call${leverage ? ` (${leverage})` : ""}: Keybots ${direction === "buy" ? "buys" : "sells"} spot, no leverage.`;
}

export interface Feed {
  /** The feed as a whole: "mixed" when both the X feed and Telegram calls are in it. */
  source: "x" | "telegram" | "mixed" | "sample";
  note: string | null;
  calls: FeedCall[];
}

export interface ReviewJson {
  reviewId: string;
  expiresAt: string;
  /** Seconds the quote lasts from when the phone gets it: count down from this, not from expiresAt (clocks differ). */
  ttlSeconds: number;
  call: {
    author: { handle: string; name: string | null } | null;
    postedAt: string | null;
    url: string | null;
    text: string;
    asset: string;
    direction: "buy" | "sell";
    /** A leveraged signal read as spot (from the feed, or pasted): what it said and the line to show. */
    signal?: Signal & { note: string };
  };
  reading: { by: "rules"; detail: string };
  trade: {
    network: string;
    venue: string;
    pay: { amount: string; symbol: "NEAR" };
    receive: { amount: string; symbol: string; min: string };
    slippagePct: 1;
    fundsSit: string;
    standIn: string | null;
  };
  mainnetQuote: { label: string; payAmount: string; receiveAmount: string; symbol: string } | null;
  /** What NEAR Intents checked for this call, in one line, and the prices it gave. */
  intents: { line: string; assetPrice: number | null; nearPrice: number };
  limits: {
    agent: string;
    agentName: "Trading Agent";
    perTrade: string;
    daily: string;
    spentToday: string;
    stopped: boolean;
    within: boolean;
    sentence: string;
    willRefuse: string | null;
    /** Who will refuse it: the contract (a limit, recorded on chain) or the AIRKEY server (Stop everything; nothing is sent). */
    refusedBy: "contract" | "server" | null;
  };
}

export interface ConfirmJson {
  /** "unknown": NEAR didn't answer, so whether it went through isn't known. */
  status: "swapped" | "blocked" | "failed" | "unknown";
  receipt: {
    id: string;
    summary: string;
    at: string;
    by: "contract" | "server";
    rule: string | null;
    reason: string | null;
    agent: string;
    pay: { amount: string; symbol: string };
    receive: { amount: string; symbol: string } | null;
    venue: string;
    standIn: string | null;
    tx: { hash: string; url: string } | null;
    /** Where the call came from. For Telegram, `author` is the group; `url` is its t.me link or null. */
    post: { url: string | null; author: string; source: "x" | "telegram" } | null;
  };
  repeat?: true;
}

/** A refusal with its HTTP status, in plain words. */
export class TradeError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

const dollars = (n: number) => "$" + (n >= 100 ? Math.round(n).toLocaleString("en-US") : n >= 1 ? n.toFixed(2) : n.toPrecision(2));

/** "NEAR Intents: ETH is a listed token at $3,120 · NEAR $2.10, so $5 is 2.38 NEAR". */
export function intentsLine(asset: string, assetPrice: number | null, nearPrice: number, usd: number, amountNear: string): string {
  const listed = assetPrice ? `${asset} is a listed token at ${dollars(assetPrice)}` : `${asset} is a listed token`;
  return `NEAR Intents: ${listed} · NEAR ${dollars(nearPrice)}, so ${dollars(usd)} is ${amountNear} NEAR`;
}

export const REVIEW_TTL_MS = 30_000;
export const MAX_USD = 10;
const FEED_MAX = 10;
/** A finished review is kept this long, so a late repeat still gets its receipt. */
const KEEP_MS = 60 * 60_000;
const QUOTE_WAIT_MS = 1500;
export const SAMPLE_NOTE = "Sample posts: the X feed didn't answer. Not real calls.";
const X_NOTE = "Calls Keybots tracks from people on X. Not every post on X.";
const telegramNote = (titles: string[]) =>
  `Messages from the Telegram ${titles.length > 1 ? "groups" : "group"} ${titles.join(", ")} where the Keybots bot is a member.`;

/** Shown when the X feed can't be reached, so the flow can still be tried. Labelled as samples everywhere. */
const SAMPLES: { minutesAgo: number; text: string; asset: string; direction: "buy" | "sell" }[] = [
  { minutesAgo: 12, text: "$SOL looks ready to run. Buying a small bag here.", asset: "SOL", direction: "buy" },
  { minutesAgo: 47, text: "Taking profits on $NEAR here, selling into this pump.", asset: "NEAR", direction: "sell" },
  { minutesAgo: 95, text: "$ETH breakout confirmed. Buying spot.", asset: "ETH", direction: "buy" },
  { minutesAgo: 140, text: "$BTC holding the range low. Adding here, stop under the wick.", asset: "BTC", direction: "buy" },
  { minutesAgo: 210, text: "$DOGE volume dying. Out of my position.", asset: "DOGE", direction: "sell" },
  { minutesAgo: 300, text: "$XRP reclaiming support. Small long, spot only.", asset: "XRP", direction: "buy" },
];

/** AIRKEY_DEMO_CALLS=on: the labelled samples sit beside the real calls, so a demo always has fresh ones. */
const demoCalls = () => (process.env.AIRKEY_DEMO_CALLS ?? "").toLowerCase() === "on";

function samples(now: number): FeedCall[] {
  return SAMPLES.map((s, i) => ({
    id: `sample-${i + 1}`,
    source: "sample",
    author: { handle: "sample", name: "Sample post" },
    postedAt: new Date(now - s.minutesAgo * 60_000).toISOString(),
    url: null,
    text: s.text,
    asset: s.asset,
    direction: s.direction,
    record: null,
  }));
}

/** "1000000000000000000000000" -> "1" (6 decimals at most). */
const nearOf = (yocto: bigint) => String(Number((yocto > 0n ? yocto : 0n) / 10n ** 18n) / 1e6);

export type TradeDeps = CommandDeps & { xfeed: XFeedClient; telegram?: TelegramSource; now?: () => number };

/** A Telegram message that read as a call, as the feed shows it. */
function telegramCall(t: TgCall): FeedCall {
  return {
    id: t.id,
    source: "telegram",
    author: { handle: t.from.username ?? t.from.first_name ?? t.chatTitle, name: t.chatTitle },
    postedAt: new Date(t.date * 1000).toISOString(),
    url: t.url,
    text: t.text,
    asset: t.asset,
    direction: t.direction,
    ...(t.signal ? { signal: { ...t.signal, note: signalNote(t.direction, t.signal.leverage) } } : {}),
    record: null,
  };
}

interface Review {
  id: string;
  createdAt: number;
  expiresAt: number;
  json: ReviewJson;
  command: string;
  minUnits: string;
  post: FollowSource | undefined;
  /** What the receipt says about where the call came from. */
  shown: { url: string | null; author: string; source: "x" | "telegram" } | null;
  state: "open" | "sending" | "done";
  result?: ConfirmJson;
}

export function tradeFlow(deps: TradeDeps) {
  const now = deps.now ?? Date.now;
  const reviews = new Map<string, Review>();
  /** The last feed's calls by id, so a review can name one. */
  let lastFeed = new Map<string, FeedCall>();

  /** the X feed's spot calls, newest first (none when the X feed doesn't answer). */
  async function xCalls(): Promise<FeedCall[]> {
    try {
      const f = await deps.xfeed.feed();
      const callers = new Map(f.callers.map((c) => [c.handle.toLowerCase(), c]));
      // Spot buys and sells only: a post that reads as a perp, or names a contract address, is left out.
      const spot = f.calls.filter((c) => !(c.text && (readCall(c.text).instrument === "perp" || namesContract(c.text))));
      const withText = spot.filter((c) => c.text);
      const picked = (withText.length ? withText : spot).slice(0, FEED_MAX);
      return picked.map((c): FeedCall => {
        const who = callers.get(c.caller);
        return {
          id: `x-${c.postId}`,
          source: "x",
          author: { handle: c.caller, name: null },
          postedAt: new Date(c.postedAt * 1000).toISOString(),
          url: postUrl(c.caller, c.postId),
          text: c.text,
          asset: c.asset,
          direction: c.direction === "up" ? "buy" : "sell",
          record: who ? { hits: who.hits, misses: Math.max(0, who.settled - who.hits) } : null,
        };
      });
    } catch {
      return [];
    }
  }

  async function feed(): Promise<Feed> {
    const fromX = await xCalls();
    const fromTelegram = (deps.telegram?.calls() ?? []).slice(0, FEED_MAX).map(telegramCall);
    const extra = demoCalls() ? samples(now()) : [];
    const calls = [...fromX, ...fromTelegram, ...extra].sort((a, b) => Date.parse(b.postedAt) - Date.parse(a.postedAt)).slice(0, FEED_MAX);
    let out: Feed;
    if (!calls.length) {
      out = { source: "sample", note: SAMPLE_NOTE, calls: samples(now()).slice(0, 3) };
    } else {
      const hasX = calls.some((c) => c.source === "x");
      const tgTitles = [...new Set(calls.filter((c) => c.source === "telegram").map((c) => c.author.name ?? ""))].filter(Boolean);
      const notes = [hasX ? X_NOTE : null, tgTitles.length ? telegramNote(tgTitles) : null, extra.length ? "Calls marked Sample are examples, not real posts." : null].filter(Boolean);
      out = { source: hasX ? (tgTitles.length ? "mixed" : "x") : "telegram", note: notes.join(" "), calls };
    }
    lastFeed = new Map(out.calls.map((c) => [c.id, c]));
    return out;
  }

  async function findCall(id: string): Promise<FeedCall | undefined> {
    const sample = samples(now()).find((c) => c.id === id);
    if (sample) return sample;
    // A Telegram call is looked up in the store itself, so it can't have scrolled out of the last feed.
    const tg = id.startsWith("tg-") ? deps.telegram?.find(id) : undefined;
    if (tg) return telegramCall(tg);
    if (!lastFeed.has(id)) await feed();
    return lastFeed.get(id);
  }

  function prune() {
    const t = now();
    for (const [id, r] of reviews) if (r.state !== "sending" && t - r.createdAt > KEEP_MS) reviews.delete(id);
  }

  async function review(body: { callId?: unknown; text?: unknown; usd?: unknown }): Promise<ReviewJson> {
    prune();
    const usd = body.usd === undefined || body.usd === null ? 1 : Number(body.usd);
    if (typeof body.usd === "string" || !Number.isFinite(usd) || usd <= 0 || usd > MAX_USD) {
      throw new TradeError(400, `usd is how many dollars to trade: more than 0, up to ${MAX_USD}.`);
    }
    const { cfg, chain, intents, rhea } = deps;

    let fc: FeedCall | undefined;
    let pasted: (Signal & { note: string }) | undefined;
    let text: string;
    let call: Call;
    if (typeof body.callId === "string" && body.callId) {
      fc = await findCall(body.callId);
      if (!fc) throw new TradeError(404, "That call isn't in the feed any more. Pull the feed again.");
      text = fc.text ?? "";
      const read = fc.text ? readCall(fc.text) : null;
      // A leveraged signal was already read as spot, on purpose: its words don't make it a perp here.
      const perp = !fc.signal && read?.instrument === "perp";
      // the X feed's asset and direction are what was recorded; the words only decide if it's a perp.
      call = {
        isCall: true,
        confidence: "high",
        asset: fc.asset,
        direction: fc.direction === "buy" ? "bullish" : "bearish",
        instrument: perp ? "perp" : "spot",
        leverage: perp ? read!.leverage : null,
        summary: `${fc.direction === "buy" ? "Bullish" : "Bearish"} spot call on ${fc.asset}.`,
      };
    } else if (typeof body.text === "string" && body.text.trim()) {
      text = body.text.trim().slice(0, 2000);
      // A pasted signal-channel post ("TAO LONG 10x") is read as spot, on purpose, and says so.
      ({ call, signal: pasted } = readPosted(text));
    } else {
      throw new TradeError(400, 'Send {"callId": "..."} from the feed, or {"text": "..."} with a copied post.');
    }

    if (!rhea?.network) throw new TradeError(501, "Reviewed trades swap on Rhea, which this server only uses on testnet.");
    const route = await routeCall(text, call, { intents, chain, tradeAgent: cfg.agents.trade, network: cfg.network, rhea, usd });
    if (route.status === "unavailable") throw new TradeError(422, route.reason);
    const asset = call.asset!;
    const to = route.side === "sell" || route.standIn ? "USDC" : asset;
    if (to === "NEAR") throw new TradeError(422, "The post says buy NEAR. A reviewed trade spends NEAR from Spend Limits, so there's nothing to buy NEAR with here.");
    const pool = rhea.route(to);
    if (!pool) throw new TradeError(422, `Keybots can't swap NEAR into ${to} here.`);

    const nearToken = (await intents!.pick("NEAR", "from")).token;
    if (!nearToken?.price) throw new TradeError(503, "NEAR Intents has no NEAR price right now, so the trade can't be sized. Try again in a moment.");
    const amountNear = String(Number((usd / nearToken.price).toFixed(4)));
    const amountIn = toYocto(amountNear);

    const target = route.side === "sell" ? "USDC" : asset;
    const [expected, state, mainnetQuote, assetPrice] = await Promise.all([
      rhea.quote(pool, amountIn).catch((e: Error) => {
        throw new TradeError(502, `Rhea didn't answer: ${String(e.message ?? e).slice(0, 160)}`);
      }),
      chain.state().catch((e: Error) => {
        throw new TradeError(502, `Couldn't read the leash's limits: ${String(e.message ?? e).slice(0, 160)}`);
      }),
      Promise.race([
        intents!
          .pick(target, "to")
          .then(async (c) => {
            if (!c.token) return null;
            const q = await intents!.quote(nearToken, c.token, amountNear);
            return { label: "NEAR Intents quote (mainnet, dry: no funds move)", payAmount: amountNear, receiveAmount: tidy(q.amountOutFormatted), symbol: target };
          })
          .catch(() => null), // No dry quote right now: the review shows without one.
        new Promise<null>((r) => setTimeout(() => r(null), QUOTE_WAIT_MS)),
      ]),
      Promise.race([
        intents!
          .pick(asset, "to")
          .then((c) => c.token?.price ?? null)
          .catch(() => null),
        new Promise<null>((r) => setTimeout(() => r(null), QUOTE_WAIT_MS)),
      ]),
    ]);

    const agentAccount = cfg.agents.trade;
    const a = state.agents.find((x) => x.account === agentAccount)?.agent;
    if (!a) throw new TradeError(503, "Spend Limits has no Trading Agent yet, so there's nothing to trade with.");
    const perTrade = BigInt(a.per_payment_cap);
    const daily = BigInt(a.daily_cap);
    // The contract starts each UTC day at zero.
    const spent = a.day === Math.floor(now() / 86_400_000) ? BigInt(a.spent_today) : 0n;
    const value = BigInt(amountIn);
    const willRefuse = state.paused
      ? "Stop everything is on: Keybots won't send it."
      : value > perTrade
        ? `Over the ${nearOf(perTrade)} NEAR per-trade limit: the contract will refuse it.`
        : spent + value > daily
          ? `Over the ${nearOf(daily)} NEAR daily limit (${nearOf(spent)} NEAR spent today): the contract will refuse it.`
          : null;

    const minUnits = minOut(expected);
    const standIn = route.standIn ? `The post is about ${asset}. Testnet has no ${asset}, so this swaps NEAR to USDC instead.` : null;
    const id = randomUUID();
    const created = now();
    const json: ReviewJson = {
      reviewId: id,
      expiresAt: new Date(created + REVIEW_TTL_MS).toISOString(),
      ttlSeconds: Math.round(REVIEW_TTL_MS / 1000),
      call: {
        author: fc ? fc.author : null,
        postedAt: fc ? fc.postedAt : null,
        url: fc ? fc.url : null,
        text: fc ? (fc.text ?? `Keybots recorded a ${fc.direction} call on ${fc.asset}. It has no post text.`) : text,
        asset,
        direction: route.side,
        ...(fc?.signal ?? pasted ? { signal: fc?.signal ?? pasted } : {}),
      },
      reading: { by: "rules", detail: "Read on the Keybots server by fixed rules, not by AI" },
      trade: {
        network: cfg.network === "mainnet" ? "NEAR mainnet" : "NEAR testnet",
        venue: `Rhea, pool ${pool.pool}`,
        pay: { amount: amountNear, symbol: "NEAR" },
        receive: { amount: fromUnits(expected, pool.decimals), symbol: pool.symbol, min: fromUnits(minUnits, pool.decimals) },
        slippagePct: 1,
        fundsSit: `In Spend Limits, ${cfg.leash}. The tokens come back to it.`,
        standIn,
      },
      mainnetQuote,
      intents: { line: intentsLine(asset, assetPrice, nearToken.price, usd, amountNear), assetPrice, nearPrice: nearToken.price },
      limits: {
        agent: agentAccount,
        agentName: "Trading Agent",
        perTrade: nearOf(perTrade),
        daily: nearOf(daily),
        spentToday: nearOf(spent),
        stopped: state.paused,
        within: willRefuse === null,
        sentence: `The Trading Agent can spend up to ${nearOf(perTrade)} NEAR a trade and ${nearOf(daily)} NEAR a day. You can stop it.`,
        willRefuse,
        refusedBy: state.paused ? "server" : willRefuse ? "contract" : null,
      },
    };
    reviews.set(id, {
      id,
      createdAt: created,
      expiresAt: created + REVIEW_TTL_MS,
      json,
      command: `swap ${amountNear} near to ${to.toLowerCase()}`,
      minUnits,
      post:
        fc?.source === "telegram"
          ? { handle: fc.author.name ?? fc.author.handle, ...(fc.url ? { postUrl: fc.url } : {}) }
          : fc?.url
            ? { handle: fc.author.handle, postUrl: fc.url }
            : undefined,
      shown:
        fc?.source === "telegram"
          ? { url: fc.url, author: fc.author.name ?? fc.author.handle, source: "telegram" }
          : fc?.url
            ? { url: fc.url, author: fc.author.handle, source: "x" }
            : null,
      state: "open",
    });
    return json;
  }

  /** The receipt the app shows, from what the chain said. A quote is never "swapped". */
  function toConfirm(r: Receipt, rv: Review): ConfirmJson {
    const x = r.swap?.executed;
    const filled = r.outcome === "swapped" && !!x?.ok && !!x.amountOut;
    const status = filled ? "swapped" : r.outcome === "blocked" ? "blocked" : "failed";
    // The leash's own `blocked` event, when the contract refused it.
    const ev = (r.events ?? [])
      .map((e) => e as { event?: string; data?: { rule?: string; reason?: string }[] })
      .find((e) => e.event === "blocked")?.data?.[0];
    const byContract = !!r.decision;
    return {
      status,
      receipt: {
        id: r.id,
        summary: r.summary ?? r.message,
        at: r.at,
        by: byContract ? "contract" : "server",
        rule: status === "blocked" && byContract ? (ev?.rule ?? r.decision?.rule ?? null) : null,
        reason: status === "swapped" ? null : status === "blocked" && byContract ? (ev?.reason ?? r.decision?.reason ?? r.message) : r.message,
        agent: r.agent?.account ?? rv.json.limits.agent,
        pay: rv.json.trade.pay,
        receive: filled ? { amount: x!.amountOut!, symbol: x!.symbolOut } : null,
        venue: rv.json.trade.venue,
        standIn: rv.json.trade.standIn,
        tx: r.tx ?? null,
        post: rv.shown,
      },
    };
  }

  async function confirm(reviewId: unknown): Promise<{ code: number; body: ConfirmJson | { error: string; expired?: true } }> {
    const rv = typeof reviewId === "string" ? reviews.get(reviewId) : undefined;
    if (!rv) return { code: 404, body: { error: "No such review. Review the trade again." } };
    if (rv.state === "done") return { code: 200, body: { ...rv.result!, repeat: true } };
    if (rv.state === "sending") return { code: 409, body: { error: "Already sending this trade." } };
    if (now() > rv.expiresAt) return { code: 409, body: { error: "This quote is more than 30 seconds old. Review it again.", expired: true } };
    // One reviewed trade at a time: a phone that lost its answer and reviews again can't send a second while the first is in flight.
    if ([...reviews.values()].some((x) => x.state === "sending")) {
      return { code: 409, body: { error: "Another trade is still being sent. Wait for its result." } };
    }
    rv.state = "sending";
    try {
      const receipt = await runCommand(deps, rv.command, "reviewed-call", rv.post, { leashDecides: true, minOut: rv.minUnits });
      rv.result = toConfirm(receipt, rv);
    } catch (e) {
      // The chain may or may not have it: never try again by itself.
      rv.result = {
        status: "unknown",
        receipt: {
          id: randomUUID(),
          summary: "NEAR didn't answer, so Keybots can't say if it went through. Check Spend Limits on nearblocks before trying again.",
          at: new Date(now()).toISOString(),
          by: "server",
          rule: null,
          reason: String((e as Error).message ?? e).slice(0, 200),
          agent: rv.json.limits.agent,
          pay: rv.json.trade.pay,
          receive: null,
          venue: rv.json.trade.venue,
          standIn: rv.json.trade.standIn,
          tx: null,
          post: rv.shown,
        },
      };
    } finally {
      rv.state = "done";
    }
    return { code: 200, body: rv.result! };
  }

  return { feed, review, confirm };
}

export type TradeFlow = ReturnType<typeof tradeFlow>;
