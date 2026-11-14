// A KOL's call, start to finish: the feed (Kall's tracked calls, or labelled
// samples) -> a review with the exact numbers (nothing sent) -> a confirm
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
import type { KallClient } from "./kall.js";
import { toYocto } from "./parse.js";
import { fromUnits, minOut } from "./rhea.js";
import type { Receipt } from "./receipts.js";

export interface FeedCall {
  id: string;
  author: { handle: string; name: string | null };
  postedAt: string;
  /** The post on X; null for a sample. */
  url: string | null;
  text: string | null;
  asset: string;
  direction: "buy" | "sell";
  record: { hits: number; misses: number } | null;
}

export interface Feed {
  source: "kall" | "sample";
  note: string | null;
  calls: FeedCall[];
}

export interface ReviewJson {
  reviewId: string;
  expiresAt: string;
  call: { author: { handle: string; name: string | null } | null; postedAt: string | null; url: string | null; text: string; asset: string; direction: "buy" | "sell" };
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
  };
}

export interface ConfirmJson {
  status: "swapped" | "blocked" | "failed";
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
    post: { url: string; author: string } | null;
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

export const REVIEW_TTL_MS = 30_000;
export const MAX_USD = 10;
const FEED_MAX = 10;
/** A finished review is kept this long, so a late repeat still gets its receipt. */
const KEEP_MS = 60 * 60_000;
const QUOTE_WAIT_MS = 1500;
export const SAMPLE_NOTE = "Sample posts: Kall's feed didn't answer. Not real calls.";
const KALL_NOTE = "Calls Kall tracks from the people it follows. Not every post on X.";

/** Shown when Kall can't be reached, so the flow can still be tried. Labelled as samples everywhere. */
const SAMPLES: { minutesAgo: number; text: string; asset: string; direction: "buy" | "sell" }[] = [
  { minutesAgo: 12, text: "$SOL looks ready to run. Buying a small bag here.", asset: "SOL", direction: "buy" },
  { minutesAgo: 47, text: "Taking profits on $NEAR here, selling into this pump.", asset: "NEAR", direction: "sell" },
  { minutesAgo: 95, text: "$ETH breakout confirmed. Buying spot.", asset: "ETH", direction: "buy" },
];

function samples(now: number): FeedCall[] {
  return SAMPLES.map((s, i) => ({
    id: `sample-${i + 1}`,
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

export type TradeDeps = CommandDeps & { kall: KallClient; now?: () => number };

interface Review {
  id: string;
  createdAt: number;
  expiresAt: number;
  json: ReviewJson;
  command: string;
  minUnits: string;
  post: FollowSource | undefined;
  state: "open" | "sending" | "done";
  result?: ConfirmJson;
}

export function tradeFlow(deps: TradeDeps) {
  const now = deps.now ?? Date.now;
  const reviews = new Map<string, Review>();
  /** The last feed's calls by id, so a review can name one. */
  let lastFeed = new Map<string, FeedCall>();

  async function feed(): Promise<Feed> {
    let out: Feed;
    try {
      const f = await deps.kall.feed();
      const callers = new Map(f.callers.map((c) => [c.handle.toLowerCase(), c]));
      // Spot buys and sells only: a post that reads as a perp, or names a contract address, is left out.
      const spot = f.calls.filter((c) => !(c.text && (readCall(c.text).instrument === "perp" || namesContract(c.text))));
      const withText = spot.filter((c) => c.text);
      const picked = (withText.length ? withText : spot).slice(0, FEED_MAX);
      const calls = picked.map((c): FeedCall => {
        const who = callers.get(c.caller);
        return {
          id: `kall-${c.postId}`,
          author: { handle: c.caller, name: null },
          postedAt: new Date(c.postedAt * 1000).toISOString(),
          url: postUrl(c.caller, c.postId),
          text: c.text,
          asset: c.asset,
          direction: c.direction === "up" ? "buy" : "sell",
          record: who ? { hits: who.hits, misses: Math.max(0, who.settled - who.hits) } : null,
        };
      });
      out = calls.length ? { source: "kall", note: KALL_NOTE, calls } : { source: "sample", note: SAMPLE_NOTE, calls: samples(now()) };
    } catch {
      out = { source: "sample", note: SAMPLE_NOTE, calls: samples(now()) };
    }
    lastFeed = new Map(out.calls.map((c) => [c.id, c]));
    return out;
  }

  async function findCall(id: string): Promise<FeedCall | undefined> {
    const sample = samples(now()).find((c) => c.id === id);
    if (sample) return sample;
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
    let text: string;
    let call: Call;
    if (typeof body.callId === "string" && body.callId) {
      fc = await findCall(body.callId);
      if (!fc) throw new TradeError(404, "That call isn't in the feed any more. Pull the feed again.");
      text = fc.text ?? "";
      const read = fc.text ? readCall(fc.text) : null;
      const perp = read?.instrument === "perp";
      // Kall's asset and direction are what was recorded; the words only decide if it's a perp.
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
      call = readCall(text);
    } else {
      throw new TradeError(400, 'Send {"callId": "..."} from the feed, or {"text": "..."} with a copied post.');
    }

    if (!rhea?.network) throw new TradeError(501, "Reviewed trades swap on Rhea, which this server only uses on testnet.");
    const route = await routeCall(text, call, { intents, chain, tradeAgent: cfg.agents.trade, network: cfg.network, rhea, usd });
    if (route.status === "unavailable") throw new TradeError(422, route.reason);
    const asset = call.asset!;
    const to = route.side === "sell" || route.standIn ? "USDC" : asset;
    if (to === "NEAR") throw new TradeError(422, "The post says buy NEAR. A reviewed trade spends NEAR from the leash, so there's nothing to buy NEAR with here.");
    const pool = rhea.route(to);
    if (!pool) throw new TradeError(422, `AIRKEY can't swap NEAR into ${to} here.`);

    const nearToken = (await intents!.pick("NEAR", "from")).token;
    if (!nearToken?.price) throw new TradeError(503, "NEAR Intents has no NEAR price right now, so the trade can't be sized. Try again in a moment.");
    const amountNear = String(Number((usd / nearToken.price).toFixed(4)));
    const amountIn = toYocto(amountNear);

    const target = route.side === "sell" ? "USDC" : asset;
    const [expected, state, mainnetQuote] = await Promise.all([
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
    ]);

    const agentAccount = cfg.agents.trade;
    const a = state.agents.find((x) => x.account === agentAccount)?.agent;
    if (!a) throw new TradeError(503, "The leash has no Trading Agent yet, so there's nothing to trade with.");
    const perTrade = BigInt(a.per_payment_cap);
    const daily = BigInt(a.daily_cap);
    // The contract starts each UTC day at zero.
    const spent = a.day === Math.floor(now() / 86_400_000) ? BigInt(a.spent_today) : 0n;
    const value = BigInt(amountIn);
    const willRefuse = state.paused
      ? "Stop everything is on: AIRKEY won't send it."
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
      call: {
        author: fc ? fc.author : null,
        postedAt: fc ? fc.postedAt : null,
        url: fc ? fc.url : null,
        text: fc ? (fc.text ?? `Kall recorded a ${fc.direction} call on ${fc.asset}. It has no post text.`) : text,
        asset,
        direction: route.side,
      },
      reading: { by: "rules", detail: "Read on the AIRKEY server by fixed rules, not by AI" },
      trade: {
        network: cfg.network === "mainnet" ? "NEAR mainnet" : "NEAR testnet",
        venue: `Rhea, pool ${pool.pool}`,
        pay: { amount: amountNear, symbol: "NEAR" },
        receive: { amount: fromUnits(expected, pool.decimals), symbol: pool.symbol, min: fromUnits(minUnits, pool.decimals) },
        slippagePct: 1,
        fundsSit: `In the leash, ${cfg.leash}. The tokens come back to it.`,
        standIn,
      },
      mainnetQuote,
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
      },
    };
    reviews.set(id, {
      id,
      createdAt: created,
      expiresAt: created + REVIEW_TTL_MS,
      json,
      command: `swap ${amountNear} near to ${to.toLowerCase()}`,
      minUnits,
      post: fc?.url ? { handle: fc.author.handle, postUrl: fc.url } : undefined,
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
        post: rv.post ? { url: rv.post.postUrl, author: rv.post.handle } : null,
      },
    };
  }

  async function confirm(reviewId: unknown): Promise<{ code: number; body: ConfirmJson | { error: string; expired?: true } }> {
    const rv = typeof reviewId === "string" ? reviews.get(reviewId) : undefined;
    if (!rv) return { code: 404, body: { error: "No such review. Review the trade again." } };
    if (rv.state === "done") return { code: 200, body: { ...rv.result!, repeat: true } };
    if (rv.state === "sending") return { code: 409, body: { error: "Already sending this trade." } };
    if (now() > rv.expiresAt) return { code: 409, body: { error: "This quote is more than 30 seconds old. Review it again.", expired: true } };
    rv.state = "sending";
    try {
      const receipt = await runCommand(deps, rv.command, "reviewed-call", rv.post, { leashDecides: true, minOut: rv.minUnits });
      rv.result = toConfirm(receipt, rv);
    } catch (e) {
      // The chain may or may not have it: never try again by itself.
      rv.result = {
        status: "failed",
        receipt: {
          id: randomUUID(),
          summary: "NEAR didn't answer, so AIRKEY can't say if it went through. Check the leash before trying again.",
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
          post: rv.post ? { url: rv.post.postUrl, author: rv.post.handle } : null,
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
