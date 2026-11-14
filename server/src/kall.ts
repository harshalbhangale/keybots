// Kall Markets' public API (our own, no key): who the tracked callers are,
// and each caller's calls with how they settled. Read-only, cached a minute,
// and a slow answer gives up after 5 s rather than holding a route up.

/** One call as Kall recorded it. `direction` is Kall's: "up" is a buy, "down" a sell. */
export interface KallCall {
  postId: string;
  asset: string;
  direction: "up" | "down";
  /** "hit" or "miss" once settled; anything else is still open. */
  status: string;
  returnBps: number | null;
  /** Unix seconds. */
  postedAt: number;
  expiresAt: number | null;
  /** The post's words, when Kall has them (the feed does; a caller's page doesn't). */
  text: string | null;
}

/** A tracked caller from Kall's feed, with their record. */
export interface KallCaller {
  handle: string;
  focus: string | null;
  tracked: boolean;
  open: number;
  settled: number;
  hits: number;
  medianBps: number | null;
}

export interface KallFeed {
  callers: KallCaller[];
  /** Open calls and settled results, by post, with their words. */
  calls: (KallCall & { caller: string })[];
}

export interface KallClient {
  feed(): Promise<KallFeed>;
  /** One caller's calls, newest first, one per post. */
  caller(handle: string): Promise<KallCall[]>;
}

const TIMEOUT_MS = 5000;
const CACHE_MS = 60_000;

type Raw = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" ? v : null);
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : null);

function toCall(r: Raw): KallCall | null {
  const postId = str(r.postId);
  const asset = str(r.asset);
  const direction = r.direction === "up" || r.direction === "down" ? r.direction : null;
  const postedAt = num(r.postedAt);
  if (!postId || !asset || !direction || postedAt === null) return null;
  return {
    postId,
    asset: asset.toUpperCase(),
    direction,
    status: str(r.status) ?? "open",
    returnBps: num(r.returnBps),
    postedAt,
    expiresAt: num(r.expiresAt) ?? num(r.deadline),
    text: str(r.text),
  };
}

/** Kall stores some posts twice (two keys, same post): keep one, newest first. */
export function onePerPost<T extends KallCall>(calls: T[]): T[] {
  const seen = new Set<string>();
  return [...calls]
    .sort((a, b) => b.postedAt - a.postedAt)
    .filter((c) => (seen.has(c.postId) ? false : (seen.add(c.postId), true)));
}

export function kallClient(base = "https://kallmarkets.vercel.app", fetcher: typeof fetch = fetch): KallClient {
  const cache = new Map<string, { at: number; value: Promise<unknown> }>();
  const get = <T>(path: string, shape: (body: Raw) => T): Promise<T> => {
    const hit = cache.get(path);
    if (hit && Date.now() - hit.at < CACHE_MS) return hit.value as Promise<T>;
    const value = (async () => {
      const res = await fetcher(`${base.replace(/\/$/, "")}${path}`, { signal: AbortSignal.timeout(TIMEOUT_MS) });
      if (!res.ok) throw new Error(`Kall answered ${res.status}`);
      return shape((await res.json()) as Raw);
    })();
    cache.set(path, { at: Date.now(), value });
    // A failed answer isn't kept: the next ask tries again.
    value.catch(() => cache.delete(path));
    return value;
  };
  return {
    feed: () =>
      get("/api/keyboard/feed", (body) => {
        const callers = (Array.isArray(body.callers) ? (body.callers as Raw[]) : []).flatMap((c) => {
          const handle = str(c.handle);
          if (!handle) return [];
          return [{ handle, focus: str(c.focus), tracked: c.tracked === true, open: num(c.open) ?? 0, settled: num(c.settled) ?? 0, hits: num(c.hits) ?? 0, medianBps: num(c.medianBps) }];
        });
        const raw = [...(Array.isArray(body.calls) ? body.calls : []), ...(Array.isArray(body.results) ? body.results : [])] as Raw[];
        const calls = raw.flatMap((r) => {
          const c = toCall(r);
          const caller = str(r.caller);
          return c && caller ? [{ ...c, caller: caller.toLowerCase() }] : [];
        });
        return { callers, calls: onePerPost(calls) };
      }),
    caller: (handle) =>
      get(`/api/callers/${encodeURIComponent(handle.toLowerCase())}`, (body) =>
        onePerPost((Array.isArray(body.calls) ? (body.calls as Raw[]) : []).flatMap((r) => toCall(r) ?? [])),
      ),
  };
}

/** For tests: callers and their calls held in memory. */
export function fakeKall(data: { callers?: KallCaller[]; calls?: Record<string, KallCall[]> } = {}): KallClient & { calls: Record<string, KallCall[]> } {
  const calls = data.calls ?? {};
  return {
    calls,
    feed: async () => ({
      callers: data.callers ?? [],
      calls: onePerPost(Object.entries(calls).flatMap(([caller, list]) => list.map((c) => ({ ...c, caller })))),
    }),
    caller: async (handle) => onePerPost(calls[handle.toLowerCase()] ?? []),
  };
}
