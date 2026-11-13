// Web search for the keyboard: a few results as cards (title, site, a line
// of text, the link), and the short answer when the search engine has one.
// Text only: no thumbnails, the keyboard has no memory to spare for images.
//
// It needs a key in server/.env: BRAVE_SEARCH_KEY (Brave Search) or
// SERPER_API_KEY (Google results through Serper). With neither, it says so
// plainly and searches nothing.

export interface SearchCard {
  id: string;
  title: string;
  url: string;
  domain: string;
  snippet?: string;
}

export interface SearchAnswer {
  title: string;
  value: string;
  source: string;
  url: string;
}

export interface SearchResult {
  provider: "brave" | "google" | "youtube";
  answer: SearchAnswer | null;
  cards: SearchCard[];
}

export class SearchNeedsKey extends Error {
  constructor() {
    super("Search needs a key");
  }
}

export type SearchEnv = { BRAVE_SEARCH_KEY?: string; SERPER_API_KEY?: string };

/** Which search is set up, without the key itself. */
export function searchProvider(env: SearchEnv = process.env): "brave" | "google" | null {
  return env.BRAVE_SEARCH_KEY ? "brave" : env.SERPER_API_KEY ? "google" : null;
}

const ENTITIES: Record<string, string> = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&#x27;": "'", "&nbsp;": " " };

/** Search engines mark the matched words with tags; the cards show plain text. */
export function stripTags(s: string): string {
  return s
    .replace(/<[^>]+>/g, "")
    .replace(/&(amp|lt|gt|quot|#39|#x27|nbsp);/g, (m) => ENTITIES[m] ?? m)
    .replace(/\s+/g, " ")
    .trim();
}

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** Only links a person can open go on a card. */
const openable = (url: unknown): url is string => typeof url === "string" && /^https?:\/\//i.test(url);

async function braveWeb(q: string, key: string, fetchImpl: typeof fetch): Promise<SearchResult> {
  const params = new URLSearchParams({ q, count: "6", safesearch: "moderate" });
  const res = await fetchImpl(`https://api.search.brave.com/res/v1/web/search?${params}`, {
    headers: { "x-subscription-token": key, accept: "application/json" },
    signal: AbortSignal.timeout(6000),
  });
  if (!res.ok) throw new Error(`Brave answered ${res.status}`);
  const data = (await res.json()) as {
    web?: { results?: { title?: string; url?: string; description?: string; meta_url?: { hostname?: string } }[] };
  };
  const cards = (data.web?.results ?? [])
    .filter((r) => openable(r.url) && r.title)
    .slice(0, 6)
    .map((r, i) => ({
      id: `brave-${i}`,
      title: stripTags(r.title!),
      url: r.url!,
      domain: r.meta_url?.hostname?.replace(/^www\./, "") ?? hostOf(r.url!),
      ...(r.description ? { snippet: stripTags(r.description).slice(0, 300) } : {}),
    }));
  return { provider: "brave", answer: null, cards };
}

async function serperWeb(q: string, key: string, fetchImpl: typeof fetch): Promise<SearchResult> {
  const res = await fetchImpl("https://google.serper.dev/search", {
    method: "POST",
    signal: AbortSignal.timeout(7000),
    headers: { "x-api-key": key, "content-type": "application/json" },
    body: JSON.stringify({ q, num: 8 }),
  });
  if (!res.ok) throw new Error(`Serper answered ${res.status}`);
  const data = (await res.json()) as {
    answerBox?: { title?: string; answer?: string; snippet?: string; snippetHighlighted?: string[]; link?: string };
    knowledgeGraph?: { title?: string; description?: string; descriptionLink?: string };
    organic?: { title?: string; link?: string; snippet?: string }[];
  };
  const google = `https://www.google.com/search?q=${encodeURIComponent(q)}`;
  let answer: SearchAnswer | null = null;
  const box = data.answerBox;
  const value = box?.answer ?? box?.snippetHighlighted?.[0] ?? box?.snippet;
  if (box && value) {
    const url = openable(box.link) ? box.link : google;
    answer = { title: stripTags(box.title ?? q), value: stripTags(value).slice(0, 400), source: hostOf(url) || "google.com", url };
  } else if (data.knowledgeGraph?.description) {
    const kg = data.knowledgeGraph;
    const url = openable(kg.descriptionLink) ? kg.descriptionLink : google;
    answer = { title: stripTags(kg.title ?? q), value: stripTags(kg.description!).slice(0, 400), source: hostOf(url) || "google.com", url };
  }
  const cards = (data.organic ?? [])
    .filter((r) => openable(r.link) && r.title)
    .slice(0, 6)
    .map((r, i) => ({
      id: `google-${i}`,
      title: stripTags(r.title!),
      url: r.link!,
      domain: hostOf(r.link!),
      ...(r.snippet ? { snippet: stripTags(r.snippet).slice(0, 300) } : {}),
    }));
  return { provider: "google", answer, cards };
}

/** Search the web. Throws SearchNeedsKey when no search key is set. */
export async function searchWeb(query: string, env: SearchEnv = process.env, fetchImpl: typeof fetch = fetch): Promise<SearchResult> {
  const q = query.trim().slice(0, 200);
  if (env.BRAVE_SEARCH_KEY) return braveWeb(q, env.BRAVE_SEARCH_KEY, fetchImpl);
  if (env.SERPER_API_KEY) return serperWeb(q, env.SERPER_API_KEY, fetchImpl);
  throw new SearchNeedsKey();
}

/** A YouTube link the keyboard can trust: youtube.com or youtu.be over https. */
export function youtubeLink(url: string | undefined): url is string {
  try {
    const u = new URL(url ?? "");
    return u.protocol === "https:" && /(^|\.)(youtube\.com|youtu\.be)$/.test(u.hostname);
  } catch {
    return false;
  }
}

/**
 * YouTube videos, through Serper's video search (the same key as web search).
 * Each card is a video: title, "channel · 2:25", and its YouTube link, which
 * Insert puts in the chat so the app shows its preview. Only YouTube links.
 */
export async function searchYouTube(query: string, env: SearchEnv = process.env, fetchImpl: typeof fetch = fetch): Promise<SearchResult> {
  const q = query.trim().slice(0, 200);
  if (!env.SERPER_API_KEY) throw new SearchNeedsKey();
  const res = await fetchImpl("https://google.serper.dev/videos", {
    method: "POST",
    signal: AbortSignal.timeout(7000),
    headers: { "x-api-key": env.SERPER_API_KEY, "content-type": "application/json" },
    body: JSON.stringify({ q, num: 10 }),
  });
  if (!res.ok) throw new Error(`Serper answered ${res.status}`);
  const data = (await res.json()) as { videos?: { title?: string; link?: string; channel?: string; duration?: string; date?: string }[] };
  const cards = (data.videos ?? [])
    .filter((v) => youtubeLink(v.link) && v.title)
    .slice(0, 8)
    .map((v, i) => ({
      id: `youtube-${i}`,
      title: stripTags(v.title!),
      url: v.link!,
      domain: [v.channel, v.duration].filter(Boolean).map((x) => stripTags(x!)).join(" · ") || "YouTube",
      ...(v.date ? { snippet: stripTags(v.date) } : {}),
    }));
  return { provider: "youtube", answer: null, cards };
}
