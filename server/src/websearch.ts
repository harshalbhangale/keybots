// Web search for the keyboard, through Serper (serper.dev). The key stays on
// this server; the phone only sees titles, links and snippets.

export interface WebResult {
  id: string;
  title: string;
  url: string;
  /** The host people recognise: "en.wikipedia.org", without "www.". */
  site: string;
  snippet: string;
}

export const SERPER_URL = "https://google.serper.dev/search";
export const RESULTS = 5;

export class SearchOff extends Error {}

const plain = (s: unknown, max: number) =>
  typeof s === "string" ? s.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim().slice(0, max) : "";

function siteOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** The top results for `query`, at most five, in Serper's order. */
export async function searchWeb(query: string, key: string, fetchImpl: typeof fetch = fetch, signal?: AbortSignal): Promise<WebResult[]> {
  if (!key) throw new SearchOff("Search isn't set up on this server");
  const timeout = AbortSignal.timeout(8_000);
  const res = await fetchImpl(SERPER_URL, {
    method: "POST",
    headers: { "x-api-key": key, "content-type": "application/json" },
    body: JSON.stringify({ q: query.slice(0, 300), num: RESULTS }),
    signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
  });
  // A fixed message: nothing from Serper's answer (or the key) is passed on.
  if (!res.ok) throw new Error(`Search answered ${res.status}`);
  const json = (await res.json()) as { organic?: { title?: unknown; link?: unknown; snippet?: unknown }[] };
  const out: WebResult[] = [];
  for (const r of json.organic ?? []) {
    const url = typeof r.link === "string" && /^https?:\/\//.test(r.link) ? r.link : "";
    const title = plain(r.title, 200);
    if (!url || !title) continue;
    out.push({ id: `r${out.length + 1}`, title, url, site: siteOf(url), snippet: plain(r.snippet, 400) });
    if (out.length === RESULTS) break;
  }
  return out;
}
