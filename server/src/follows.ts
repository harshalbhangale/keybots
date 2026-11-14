// Following KOLs: the X handles the owner follows, the rules for each, and
// the trades their calls led to. Calls come from Kall (kall.ts). A call that
// passes the owner's rules becomes the same small swap a copied call's chip
// offers, and runs as a "follow" command: the Trading Agent's caps on chain
// still apply, and the receipt names the KOL and the post.
//
// Nothing trades unless the server runs with AIRKEY_AUTO_TRADE=on. Off, every
// call is still checked and recorded as what it would have done.
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import type { FollowSource } from "./agent.js";
import { readCall, type Call, type CallRoute } from "./calls.js";
import type { KallCall, KallClient } from "./kall.js";
import type { Receipt } from "./receipts.js";

export interface FollowRules {
  /** Trade their calls by themselves. */
  auto: boolean;
  /** Dollars each trade spends. */
  perCallUsd: number;
  /** Dollars all their trades may spend in a UTC day. */
  perDayUsd: number;
  /** "buy": only their buy calls. "both": sells too. */
  sides: "buy" | "both";
  /** Skip a call whose words read as unsure. */
  highOnly: boolean;
  /** Stop after this many misses in a row (0: never). */
  stopAfterMisses: number;
}

export const DEFAULT_RULES: FollowRules = { auto: true, perCallUsd: 1, perDayUsd: 3, sides: "buy", highOnly: true, stopAfterMisses: 3 };

export interface StoredFollow extends FollowRules {
  /** As the owner wrote it, without the @. Looked up in lower case. */
  handle: string;
  addedAt: string;
  spentTodayUsd: number;
  /** The UTC day `spentTodayUsd` is for ("2026-11-14"). */
  spentDay: string;
  lastSeenPostId: string | null;
  /** When the newest call checked for them was posted. */
  lastCallAt: string | null;
  missesInRow: number;
  /** Misses only count from here: when they were followed, or when auto was turned back on. */
  missesFrom: string;
  pausedReason: string | null;
}

export interface KolRecord {
  hits: number;
  misses: number;
  open: number;
  avgReturnBps: number | null;
}

/** What the keyboard and the app get for a follow. */
export interface FollowJson extends FollowRules {
  handle: string;
  addedAt: string;
  spentTodayUsd: number;
  lastCallAt: string | null;
  missesInRow: number;
  pausedReason: string | null;
  record: KolRecord | null;
}

export interface AutoTrade {
  id: string;
  handle: string;
  postId: string;
  postUrl: string;
  asset: string;
  side: "buy" | "sell";
  at: string;
  status: "traded" | "skipped" | "failed";
  reason: string | null;
  /** One plain line for the keyboard. */
  message: string;
  usd: number;
  receiptId: string | null;
  txUrl: string | null;
  /** The owner asked for this call (the latest one) by hand, rather than the poller finding it. */
  onRequest: boolean;
}

export const HANDLE = /^@?[A-Za-z0-9_]{1,15}$/;
export const postUrl = (handle: string, postId: string) => `https://x.com/${handle}/status/${postId}`;
const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const key = (handle: string) => handle.replace(/^@/, "").toLowerCase();

/** Today's spend: yesterday's doesn't count. */
export function spentToday(f: StoredFollow, now = Date.now()): number {
  return f.spentDay === utcDay(now) ? f.spentTodayUsd : 0;
}

// ---------------------------------------------------------------------------
// The store: follows.json (the follows) and follow-trades.jsonl (what their calls led to).
// ---------------------------------------------------------------------------

export interface FollowStore {
  list(): StoredFollow[];
  get(handle: string): StoredFollow | undefined;
  /** Add a follow, or change its rules. Turning auto back on lifts a pause and starts the misses over. */
  upsert(handle: string, rules: Partial<FollowRules>, now?: number): StoredFollow;
  update(handle: string, patch: Partial<StoredFollow>): StoredFollow | undefined;
  remove(handle: string): boolean;
  addTrade(t: AutoTrade): void;
  /** Newest first. */
  trades(limit?: number): AutoTrade[];
}

function followStore(io: { read(): StoredFollow[]; write(all: StoredFollow[]): void; readTrades(): AutoTrade[]; appendTrade(t: AutoTrade): void }): FollowStore {
  const get = (handle: string) => io.read().find((f) => key(f.handle) === key(handle));
  const update = (handle: string, patch: Partial<StoredFollow>) => {
    const all = io.read();
    const i = all.findIndex((f) => key(f.handle) === key(handle));
    if (i < 0) return undefined;
    all[i] = { ...all[i]!, ...patch };
    io.write(all);
    return all[i];
  };
  return {
    list: () => io.read(),
    get,
    upsert(handle, rules, now = Date.now()) {
      const display = handle.replace(/^@/, "");
      const was = get(display);
      if (!was) {
        const at = new Date(now).toISOString();
        const f: StoredFollow = {
          handle: display,
          ...DEFAULT_RULES,
          ...rules,
          addedAt: at,
          spentTodayUsd: 0,
          spentDay: utcDay(now),
          lastSeenPostId: null,
          lastCallAt: null,
          missesInRow: 0,
          missesFrom: at,
          pausedReason: null,
        };
        io.write([...io.read(), f]);
        return f;
      }
      const resume = rules.auto === true && was.pausedReason ? { pausedReason: null, missesInRow: 0, missesFrom: new Date(now).toISOString() } : {};
      return update(display, { ...rules, handle: display, ...resume })!;
    },
    update,
    remove(handle) {
      const all = io.read();
      const left = all.filter((f) => key(f.handle) !== key(handle));
      if (left.length === all.length) return false;
      io.write(left);
      return true;
    },
    addTrade: (t) => io.appendTrade(t),
    trades: (limit = 50) => [...io.readTrades()].reverse().slice(0, limit),
  };
}

export function fileFollows(dir: string): FollowStore {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, "follows.json");
  const tradesFile = join(dir, "follow-trades.jsonl");
  return followStore({
    read: () => (existsSync(file) ? (JSON.parse(readFileSync(file, "utf8")) as StoredFollow[]) : []),
    write: (all) => writeFileSync(file, JSON.stringify(all, null, 2)),
    readTrades: () =>
      existsSync(tradesFile)
        ? readFileSync(tradesFile, "utf8")
            .split("\n")
            .filter(Boolean)
            .map((l) => JSON.parse(l) as AutoTrade)
        : [],
    appendTrade: (t) => appendFileSync(tradesFile, JSON.stringify(t) + "\n"),
  });
}

export function memoryFollows(): FollowStore {
  let follows: StoredFollow[] = [];
  const trades: AutoTrade[] = [];
  return followStore({
    read: () => follows.map((f) => ({ ...f })),
    write: (all) => void (follows = all.map((f) => ({ ...f }))),
    readTrades: () => trades,
    appendTrade: (t) => void trades.push(t),
  });
}

/** A caller's record from their calls on Kall: settled hits and misses, open calls, and the average return of the settled ones. */
export function recordOf(calls: KallCall[]): KolRecord {
  const settled = calls.filter((c) => c.status === "hit" || c.status === "miss");
  const returns = settled.map((c) => c.returnBps).filter((n): n is number => n !== null);
  return {
    hits: settled.filter((c) => c.status === "hit").length,
    misses: settled.filter((c) => c.status === "miss").length,
    open: calls.length - settled.length,
    avgReturnBps: returns.length ? Math.round(returns.reduce((a, b) => a + b, 0) / returns.length) : null,
  };
}

export function followJson(f: StoredFollow, record: KolRecord | null, now = Date.now()): FollowJson {
  return {
    handle: f.handle,
    auto: f.auto,
    perCallUsd: f.perCallUsd,
    perDayUsd: f.perDayUsd,
    sides: f.sides,
    highOnly: f.highOnly,
    stopAfterMisses: f.stopAfterMisses,
    addedAt: f.addedAt,
    spentTodayUsd: spentToday(f, now),
    lastCallAt: f.lastCallAt,
    missesInRow: f.missesInRow,
    pausedReason: f.pausedReason,
    record,
  };
}

/** Checks a POST /v1/follows body. Returns the handle and the rules it sets, or what's wrong in plain words. */
export function parseFollow(body: unknown): { handle: string; rules: Partial<FollowRules> } | { error: string } {
  const b = (body ?? {}) as Record<string, unknown>;
  if (typeof b.handle !== "string" || !HANDLE.test(b.handle.trim())) return { error: "Send an X handle, like @CryptoKaleo" };
  const rules: Partial<FollowRules> = {};
  const money = (name: "perCallUsd" | "perDayUsd", max: number) => {
    const v = b[name];
    if (v === undefined) return null;
    if (typeof v !== "number" || !Number.isFinite(v) || v <= 0 || v > max) return `${name} is dollars, more than 0 and at most ${max}`;
    rules[name] = Math.round(v * 100) / 100;
    return null;
  };
  for (const name of ["auto", "highOnly"] as const) {
    if (b[name] === undefined) continue;
    if (typeof b[name] !== "boolean") return { error: `${name} is true or false` };
    rules[name] = b[name] as boolean;
  }
  const bad = money("perCallUsd", 100) ?? money("perDayUsd", 1000);
  if (bad) return { error: bad };
  if (b.sides !== undefined) {
    if (b.sides !== "buy" && b.sides !== "both") return { error: 'sides is "buy" or "both"' };
    rules.sides = b.sides;
  }
  if (b.stopAfterMisses !== undefined) {
    const n = b.stopAfterMisses;
    if (typeof n !== "number" || !Number.isInteger(n) || n < 0 || n > 20) return { error: "stopAfterMisses is a whole number from 0 (never) to 20" };
    rules.stopAfterMisses = n;
  }
  return { handle: b.handle.trim().replace(/^@/, ""), rules };
}

// ---------------------------------------------------------------------------
// The poller: read each followed handle's new calls on Kall, apply the rules,
// and run the ones that pass.
// ---------------------------------------------------------------------------

export interface FollowCtx {
  follows: FollowStore;
  kall: KallClient;
  /** AIRKEY_AUTO_TRADE=on. Off, calls are only recorded as what would have happened. */
  autoTrade: boolean;
  /** routeCall with the dollars to spend: the token check, the command, the testnet stand-in. */
  route(text: string, call: Call, usd: number): Promise<CallRoute>;
  /** runCommand as a "follow" command: the Trading Agent's path, with the KOL and post on the receipt. */
  run(command: string, from: FollowSource): Promise<Receipt>;
  now?: () => number;
}

export interface FollowPoller {
  /** Check one handle now. `latest`: take their newest call even if it's older than the follow (the owner asked). */
  poll(handle: string, opts?: { latest?: boolean }): Promise<AutoTrade[]>;
  /** Every follow with auto on and not paused. */
  pollAll(): Promise<AutoTrade[]>;
}

const money = (n: number) => `$${Number(n.toFixed(2))}`;
const isSettled = (c: KallCall) => c.status === "hit" || c.status === "miss";

/** Leading misses among settled calls posted since `from`, newest first. */
export function missesInRow(calls: KallCall[], fromSec: number): number {
  let n = 0;
  for (const c of calls.filter((c) => isSettled(c) && c.postedAt >= fromSec)) {
    if (c.status !== "miss") break;
    n++;
  }
  return n;
}

export function followPoller(ctx: FollowCtx): FollowPoller {
  const now = () => ctx.now?.() ?? Date.now();
  // One check per handle at a time: the 60 s poller and a "check now" never trade the same call twice.
  const running = new Map<string, Promise<unknown>>();
  const serial = <T>(handle: string, job: () => Promise<T>): Promise<T> => {
    const k = key(handle);
    const next = (running.get(k) ?? Promise.resolve()).catch(() => undefined).then(job);
    running.set(k, next);
    void next.finally(() => running.get(k) === next && running.delete(k)).catch(() => undefined);
    return next;
  };

  async function check(handle: string, latest: boolean): Promise<AutoTrade[]> {
    let f = ctx.follows.get(handle);
    if (!f) return [];
    const calls = await ctx.kall.caller(f.handle);
    // The post's words, when Kall's feed has them: only to judge how sure the call is.
    const words = new Map<string, string>();
    try {
      for (const c of (await ctx.kall.feed()).calls) if (c.text && c.caller === key(f.handle)) words.set(c.postId, c.text);
    } catch {
      // No words: Kall having recorded the call is enough.
    }

    // Misses in a row, counted only from when they were followed (or auto was turned back on).
    const misses = missesInRow(calls, Date.parse(f.missesFrom) / 1000);
    const pause =
      !f.pausedReason && f.stopAfterMisses > 0 && misses >= f.stopAfterMisses
        ? `@${f.handle} missed ${misses} calls in a row, so auto-trading stopped for them. Turn auto back on to start again.`
        : f.pausedReason;
    f = ctx.follows.update(f.handle, { missesInRow: misses, pausedReason: pause })!;

    const done = new Set(ctx.follows.trades(10_000).filter((t) => key(t.handle) === key(f!.handle)).map((t) => t.postId));
    let todo: KallCall[];
    if (latest) {
      todo = calls.slice(0, 1);
      // Asked again for a call that already traded: the same trade, not a second one.
      const traded = ctx.follows.trades(10_000).find((t) => key(t.handle) === key(f!.handle) && t.postId === todo[0]?.postId && t.status === "traded");
      if (traded) return [traded];
    } else {
      // Never a call from before the follow, and never the same call twice. Oldest first.
      const since = Date.parse(f.addedAt) / 1000;
      todo = calls.filter((c) => c.postedAt >= since && !done.has(c.postId)).reverse();
    }

    const out: AutoTrade[] = [];
    for (const call of todo) {
      const t = await decide(f, call, words.get(call.postId) ?? null, latest);
      ctx.follows.addTrade(t);
      out.push(t);
      const seenAt = new Date(call.postedAt * 1000).toISOString();
      const patch: Partial<StoredFollow> = {};
      if (!f.lastCallAt || seenAt >= f.lastCallAt) Object.assign(patch, { lastCallAt: seenAt, lastSeenPostId: call.postId });
      if (t.status === "traded") Object.assign(patch, { spentTodayUsd: spentToday(f, now()) + t.usd, spentDay: utcDay(now()) });
      f = ctx.follows.update(f.handle, patch)!;
    }
    return out;
  }

  /** One call, through the owner's rules, then the Trading Agent's path. */
  async function decide(f: StoredFollow, call: KallCall, text: string | null, onRequest: boolean): Promise<AutoTrade> {
    const side = call.direction === "up" ? "buy" : "sell";
    const who = `@${f.handle}`;
    const usd = f.perCallUsd;
    const base = {
      id: randomUUID(),
      handle: f.handle,
      postId: call.postId,
      postUrl: postUrl(f.handle, call.postId),
      asset: call.asset,
      side,
      at: new Date(now()).toISOString(),
      usd,
      receiptId: null,
      txUrl: null,
      onRequest,
    } as const;
    const skip = (reason: string, message: string): AutoTrade => ({ ...base, status: "skipped", reason, message });
    const fail = (reason: string, message: string, r?: Receipt): AutoTrade => ({ ...base, status: "failed", reason, message, receiptId: r?.id ?? null, txUrl: r?.tx?.url ?? null });

    if (f.pausedReason) return skip(f.pausedReason, `Skipped: ${call.asset} call from ${who}. ${f.pausedReason}`);
    if (!f.auto) return skip(`Auto is off for ${who}`, `Skipped: ${call.asset} call from ${who}, auto is off for them`);
    if (!onRequest && call.expiresAt && call.expiresAt * 1000 < now()) {
      return skip("The call had already ended", `Skipped: ${who}'s ${call.asset} call had already ended`);
    }
    if (side === "sell" && f.sides === "buy") return skip("It's a sell, and you follow buys only", `Skipped: ${call.asset} call from ${who} is a sell, you follow buys only`);
    // Kall recorded it, so it counts as sure, unless the post's own words read as unsure.
    if (f.highOnly && text && readCall(text).confidence === "low") {
      return skip("The post reads as unsure", `Skipped: ${who}'s ${call.asset} post reads as unsure, and you follow sure calls only`);
    }
    if (spentToday(f, now()) + usd > f.perDayUsd + 1e-9) return skip(`Over your ${money(f.perDayUsd)} a day`, `Skipped: over your ${money(f.perDayUsd)} a day for ${who}`);

    // The same route a copied call gets: token checked on NEAR Intents, spot only, testnet stand-in.
    // The post's words go along only so a contract address in them still stops it.
    const asCall: Call = {
      isCall: true,
      confidence: "high",
      asset: call.asset,
      direction: side === "buy" ? "bullish" : "bearish",
      instrument: "spot",
      leverage: null,
      summary: `${side === "buy" ? "Bullish" : "Bearish"} spot call on ${call.asset}.`,
    };
    const route = await ctx.route(text ?? `${side === "buy" ? "buying" : "selling"} $${call.asset}`, asCall, usd);
    if (route.status !== "available") {
      const why = /Token check/.test(route.reason)
        ? `${call.asset} isn't a token we could verify`
        : /short/.test(route.reason)
          ? `you hold no ${call.asset} to sell`
          : /contract address/.test(route.reason)
            ? "the post names a contract address, so AIRKEY won't guess the token"
            : `${call.asset} can't be traded here`;
      return skip(why.charAt(0).toUpperCase() + why.slice(1), `Skipped: ${call.asset} call from ${who}, ${why}`);
    }

    const what = side === "buy" ? `${money(usd)} of ${call.asset}` : `${money(usd)} of NEAR for USDC`;
    const standIn = route.standIn ? " (testnet: NEAR → USDC)" : "";
    if (!ctx.autoTrade) {
      return skip("Auto-trading is off on this server", `Would have ${side === "buy" ? "bought" : "sold"} ${what} for you${standIn}, but auto-trading is off on this server`);
    }

    let r: Receipt;
    try {
      r = await ctx.run(route.command, { handle: f.handle, postUrl: base.postUrl });
    } catch {
      return fail("NEAR didn't answer", `Not traded: NEAR didn't answer for ${who}'s ${call.asset} call`);
    }
    if (r.outcome === "swapped") {
      return { ...base, status: "traded", reason: null, message: `${side === "buy" ? "Bought" : "Sold"} ${what} for you${standIn}`, receiptId: r.id, txUrl: r.tx?.url ?? null };
    }
    if (r.outcome === "blocked") {
      // The plain summary says which limit, without rule codes.
      const why = r.summary?.replace(/^Blocked:\s*/, "") ?? "your limits stopped it";
      return { ...fail(why, `Not traded: ${why}`, r), status: "skipped" };
    }
    if (r.outcome === "quoted") return fail("Only a quote came back", `Not traded: only a quote came back for ${call.asset}, nothing was swapped`, r);
    return fail("The swap didn't fill", "Not traded: the swap didn't fill. Your NEAR is safe", r);
  }

  return {
    poll: (handle, opts = {}) => serial(handle, () => check(handle, opts.latest === true)),
    async pollAll() {
      const out: AutoTrade[] = [];
      for (const f of ctx.follows.list()) {
        if (!f.auto || f.pausedReason) continue;
        try {
          out.push(...(await serial(f.handle, () => check(f.handle, false))));
        } catch (e) {
          // One handle Kall can't answer for doesn't stop the rest.
          console.error(`follows: @${f.handle}: ${(e as Error).message}`);
        }
      }
      return out;
    },
  };
}
