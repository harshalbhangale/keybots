// GIFs for the keyboard's emoji board, from KLIPY (the free GIF API that
// replaced Tenor's). The keyboard asks this server; this server asks KLIPY
// with the app key from the environment (KLIPY_APP_KEY, or KLIPY_API_KEY).
// The key stays here: it is never sent to the phone, never in an answer and
// never in an error. KLIPY_BASE_URL points somewhere else (a fake, for tests).

export interface GifItem {
  id: string;
  title: string;
  /** A small animated GIF for the grid. */
  preview: string;
  pw: number | null;
  ph: number | null;
  /** The medium GIF that goes on the pasteboard. */
  url: string;
  w: number | null;
  h: number | null;
}

export interface GifPage {
  items: GifItem[];
  next: number | null;
  attribution: string;
}

export type GifEnv = { KLIPY_APP_KEY?: string; KLIPY_API_KEY?: string; KLIPY_BASE_URL?: string };

export const KLIPY_ATTRIBUTION = "Powered by KLIPY";
const DEFAULT_BASE = "https://api.klipy.com/api/v1/";
const TIMEOUT_MS = 5000;
const CACHE_MS = 60_000;
const CACHE_MAX = 200;
const PER_PAGE = 24;

/** No key on this server: the board says GIFs aren't set up. */
export class GifsUnavailable extends Error {
  constructor() {
    super("GIFs aren't set up on this server");
  }
}

/** KLIPY didn't answer, or answered something else. The message never carries the URL (it holds the key). */
export class GifsDown extends Error {
  constructor(public status?: number) {
    super(status ? `KLIPY answered ${status}` : "KLIPY didn't answer");
  }
}

export interface GifClient {
  readonly ready: boolean;
  /** Trending when `q` is empty, a search otherwise. Pages start at 1. */
  page(q: string, page: number): Promise<GifPage>;
}

type Variant = { url: string; w: number | null; h: number | null };

function variant(file: Record<string, unknown>, sizes: string[], formats: string[]): Variant | null {
  for (const size of sizes) {
    const set = file[size];
    if (!set || typeof set !== "object") continue;
    for (const format of formats) {
      const f = (set as Record<string, unknown>)[format] as { url?: unknown; width?: unknown; height?: unknown } | undefined;
      if (f && typeof f.url === "string" && f.url.startsWith("https://")) {
        return { url: f.url, w: typeof f.width === "number" ? f.width : null, h: typeof f.height === "number" ? f.height : null };
      }
    }
  }
  return null;
}

/**
 * KLIPY's envelope: {result, data: {data: [items], current_page, has_next}};
 * each item has `file.{hd,md,sm,xs}.{gif,webp,...}`. Ads are skipped.
 */
export function parseKlipy(body: unknown): GifPage {
  const outer = body as { result?: unknown; data?: { data?: unknown; current_page?: unknown; has_next?: unknown } } | null;
  if (!outer || outer.result === false || !outer.data || !Array.isArray(outer.data.data)) throw new GifsDown();
  const items: GifItem[] = [];
  for (const raw of outer.data.data as Record<string, unknown>[]) {
    if (!raw || raw.type === "ad" || raw.content !== undefined) continue;
    const file = raw.file as Record<string, unknown> | undefined;
    if (!file || typeof file !== "object") continue;
    // The grid animates a small one; the message gets a medium GIF.
    const preview = variant(file, ["xs", "sm", "md"], ["gif", "webp"]);
    const full = variant(file, ["md", "sm", "hd"], ["gif"]);
    if (!preview || !full) continue;
    const id = String(raw.slug ?? raw.id ?? "");
    if (!id) continue;
    items.push({
      id,
      title: typeof raw.title === "string" ? raw.title.slice(0, 120) : "",
      preview: preview.url,
      pw: preview.w,
      ph: preview.h,
      url: full.url,
      w: full.w,
      h: full.h,
    });
  }
  const current = typeof outer.data.current_page === "number" ? outer.data.current_page : 1;
  return { items, next: outer.data.has_next === true ? current + 1 : null, attribution: KLIPY_ATTRIBUTION };
}

export function gifClient(env: GifEnv = process.env, fetchImpl: typeof fetch = fetch, now: () => number = Date.now): GifClient {
  const key = (env.KLIPY_APP_KEY?.trim() || env.KLIPY_API_KEY?.trim()) ?? "";
  const base = (env.KLIPY_BASE_URL?.trim() || DEFAULT_BASE).replace(/\/*$/, "/");
  const cache = new Map<string, { at: number; page: GifPage }>();

  return {
    ready: key.length > 0,
    async page(q, page) {
      if (!key) throw new GifsUnavailable();
      const cacheKey = `${q}\n${page}`;
      const hit = cache.get(cacheKey);
      if (hit && now() - hit.at < CACHE_MS) return hit.page;

      const url = new URL(`${base}${encodeURIComponent(key)}/gifs/${q ? "search" : "trending"}`);
      url.searchParams.set("page", String(page));
      url.searchParams.set("per_page", String(PER_PAGE));
      url.searchParams.set("customer_id", "airkey");
      url.searchParams.set("locale", "en");
      url.searchParams.set("content_filter", "high");
      url.searchParams.set("format_filter", "gif");
      if (q) url.searchParams.set("q", q);

      let res: Response;
      try {
        res = await fetchImpl(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
      } catch {
        throw new GifsDown();
      }
      if (!res.ok) throw new GifsDown(res.status);
      let body: unknown;
      try {
        body = await res.json();
      } catch {
        throw new GifsDown();
      }
      const parsed = parseKlipy(body);
      cache.set(cacheKey, { at: now(), page: parsed });
      if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value!);
      return parsed;
    },
  };
}
