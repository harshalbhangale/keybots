// A small, read-only Telegram source for trade calls. A bot sits in a group
// (or is an admin of a channel); this long-polls the Bot API's getUpdates,
// keeps the messages that read as a spot buy or sell call, and the feed shows
// them next to the X feed's. It never sends anything, answers no commands, and the
// message text is only ever shown and read by the fixed rules in calls.ts:
// it is never given to an AI and never put in a prompt.
//
// The bot token is built into the request URL inside one function and is
// scrubbed from every error. It is never logged, never returned.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { namesContract, readCall } from "./calls.js";

/** One call seen in a Telegram chat. `date` is Telegram's: unix seconds. */
export interface TgCall {
  id: string;
  chatId: string;
  chatTitle: string;
  from: { username?: string; first_name?: string };
  date: number;
  text: string;
  /** Public t.me link, only when the chat has a username. */
  url: string | null;
  asset: string;
  direction: "buy" | "sell";
  /** A leveraged signal ("TAO LONG 10x") that Keybots reads as spot, with what it said. */
  signal?: Signal;
}

/** What a leveraged signal said. Keybots never uses the leverage: it buys or sells spot. */
export interface Signal {
  leverage: string | null;
  targets: string[];
  stop: string | null;
}

export interface TelegramStatus {
  configured: boolean;
  bot: string | null;
  groups: { title: string; messages: number }[];
  lastMessageAt: string | null;
  /** The last poll's failure in plain words (token scrubbed), or null. */
  error: string | null;
}

/** What the feed and the review read. */
export interface TelegramSource {
  readonly configured: boolean;
  /** The calls kept, newest first. */
  calls(): TgCall[];
  find(id: string): TgCall | undefined;
  status(): Promise<TelegramStatus>;
  /** Start the long-poll loop (does nothing without a token). */
  start(): void;
  stop(): void;
  /** One getUpdates round: the number of updates it handled. Exposed for tests. */
  pollOnce(timeoutSec?: number): Promise<number>;
}

export const KEEP = 50;
export const MAX_RAW = 1500;
export const MAX_SHOWN = 600;
const POLL_SECONDS = 25;
const TOKEN_SHAPE = /^\d{3,}:[A-Za-z0-9_-]{20,}$/;

/** A usable bot token, or "" (a stray newline is trimmed; anything odd is refused rather than put in a URL). */
export function cleanToken(raw: string | undefined): string {
  const t = (raw ?? "").trim();
  return TOKEN_SHAPE.test(t) ? t : "";
}

/** "-100123, -100456" -> ["-100123","-100456"] */
export function parseChatIds(s: string | undefined): string[] {
  return (s ?? "").split(",").map((x) => x.trim()).filter(Boolean);
}

/** For display: control characters become spaces, runs of spaces one, at most 600 characters. */
export function tidyText(s: string): string {
  const t = s.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]+/gu, " ").replace(/\s+/g, " ").trim();
  return t.length > MAX_SHOWN ? `${t.slice(0, MAX_SHOWN - 1).trimEnd()}…` : t;
}

/**
 * Does this message read as a spot buy or sell call? Same fixed rules as the
 * the X feed: a ticker with a direction, not a perp, no contract address.
 */
export function readAsCall(text: string): { asset: string; direction: "buy" | "sell"; signal?: Signal } | null {
  if (namesContract(text)) return null;
  const c = readCall(text);
  if (c.isCall && c.asset && c.direction && c.instrument === "spot") {
    return { asset: c.asset, direction: c.direction === "bullish" ? "buy" : "sell" };
  }
  return readSignal(text);
}

const NOT_TICKERS = new Set(["LONG", "SHORT", "BUY", "SELL", "ENTER", "ENTRY", "TARGET", "TARGETS", "STOP", "SL", "TP", "USDT", "USD", "PERP", "CROSS", "ISOLATED", "MARKET", "LEVERAGE", "VIP", "SIGNAL", "NEW"]);
const PRICE = /\d+(?:\.\d+)?/g;

/**
 * A signal-channel post: "TAO LONG 10x", "#BTC/USDT SHORT (20x)", "LONG $ETH".
 * Read as spot: LONG is a buy, SHORT a sell, and the leverage, targets and stop
 * are kept only to show. Fixed rules, never an AI.
 */
export function readSignal(text: string): { asset: string; direction: "buy" | "sell"; signal: Signal } | null {
  const head = text.split("\n").map((l) => l.trim()).filter(Boolean).slice(0, 3).join(" ");
  const tick = "[#$]?([A-Z][A-Z0-9]{1,9})(?:\\s*\\/\\s*USDT?|USDT|\\s*PERP)?";
  const m =
    new RegExp(`(?:^|\\s)${tick}\\s*[:\\-–]?\\s*\\b(LONG|SHORT)\\b`).exec(head) ??
    new RegExp(`\\b(LONG|SHORT)\\b\\s*[:\\-–]?\\s*${tick}(?![a-z])`).exec(head);
  if (!m) return null;
  const [raw, side] = m[1] === "LONG" || m[1] === "SHORT" ? [m[2], m[1]] : [m[1], m[2]];
  // "SOLUSDT" is SOL quoted in USDT.
  const asset = raw && raw.length > 4 ? raw.replace(/(USDT|USDC|USD|PERP)$/, "") : raw;
  if (!asset || NOT_TICKERS.has(asset)) return null;
  const lev = /(?:^|[\s(\[x×])(\d{1,3})\s*[x×](?![a-z])/i.exec(head) ?? /[x×]\s*(\d{1,3})\b/i.exec(head);
  const line = (word: RegExp) => text.split("\n").find((l) => word.test(l)) ?? "";
  const targets = (line(/target|tp\b/i).match(PRICE) ?? []).slice(0, 6);
  const stop = (line(/stop|\bsl\b/i).match(PRICE) ?? [])[0] ?? null;
  return { asset, direction: side === "LONG" ? "buy" : "sell", signal: { leverage: lev ? `${lev[1]}x` : null, targets, stop } };
}

type Raw = Record<string, unknown>;
const obj = (v: unknown): Raw | null => (v && typeof v === "object" && !Array.isArray(v) ? (v as Raw) : null);
const str = (v: unknown) => (typeof v === "string" && v ? v : undefined);

function fromJsonl(line: string): TgCall | null {
  try {
    const r = obj(JSON.parse(line));
    if (!r) return null;
    const from = obj(r.from) ?? {};
    const dir = r.direction === "buy" || r.direction === "sell" ? r.direction : null;
    if (typeof r.id !== "string" || !r.id.startsWith("tg-") || typeof r.text !== "string" || typeof r.date !== "number" || !dir) return null;
    const asset = str(r.asset);
    const chatId = str(r.chatId);
    const chatTitle = str(r.chatTitle);
    if (!asset || !chatId || !chatTitle) return null;
    return {
      id: r.id,
      chatId,
      chatTitle: tidyText(chatTitle).slice(0, 80),
      from: { username: str(from.username), first_name: str(from.first_name) },
      date: r.date,
      text: tidyText(r.text),
      url: typeof r.url === "string" && /^https:\/\/t\.me\//.test(r.url) ? r.url : null,
      asset,
      direction: dir,
      ...(obj(r.signal) ? { signal: obj(r.signal) as unknown as Signal } : {}),
    };
  } catch {
    return null;
  }
}

export function telegramSource(opts: {
  token: string;
  /** Only these chats; empty means any group the bot is in. */
  chatIds?: string[];
  /** Where telegram-calls.jsonl lives; none keeps calls in memory only. */
  dataDir?: string;
  fetcher?: typeof fetch;
  /** Waits between failed polls (tests make it 0). */
  retryMs?: number;
}): TelegramSource {
  const token = cleanToken(opts.token);
  const fetcher = opts.fetcher ?? fetch;
  const allow = new Set((opts.chatIds ?? []).map(String));
  const file = opts.dataDir ? join(opts.dataDir, "telegram-calls.jsonl") : null;

  let kept: TgCall[] = [];
  const groups = new Map<string, { title: string; messages: number }>();
  let lastMessageAt: number | null = null;
  let offset = 0;
  let bot: string | null = null;
  let error: string | null = null;
  let running = false;
  let abort: AbortController | null = null;

  const scrub = (s: string) => {
    let out = token ? s.split(token).join("[token]") : s;
    out = out.replace(/bot\d+:[A-Za-z0-9_-]+/g, "bot[token]");
    return out.slice(0, 160);
  };

  // What a restart keeps: the calls in the file, newest 50.
  if (file && existsSync(file)) {
    try {
      const seen = new Set<string>();
      const all = readFileSync(file, "utf8")
        .split("\n")
        .flatMap((l) => (l.trim() ? (fromJsonl(l) ?? []) : []))
        .filter((c) => (seen.has(c.id) ? false : (seen.add(c.id), true)));
      kept = all.sort((a, b) => b.date - a.date).slice(0, KEEP);
      for (const c of kept) {
        const g = groups.get(c.chatId) ?? { title: c.chatTitle, messages: 0 };
        g.messages += 1;
        groups.set(c.chatId, g);
      }
      lastMessageAt = kept[0]?.date ?? null;
    } catch {
      // An unreadable file starts empty; the next call is appended after it.
    }
  }

  /** Telegram's Bot API, one method. The token is only ever inside this function. */
  async function api(method: string, body: Raw, timeoutMs: number, signal?: AbortSignal): Promise<unknown> {
    const signals = [AbortSignal.timeout(timeoutMs), ...(signal ? [signal] : [])];
    try {
      const res = await fetcher(`https://api.telegram.org/bot${token}/${method}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.any(signals),
      });
      let json: Raw | null = null;
      try {
        json = obj(await res.json());
      } catch {
        // Not JSON: the status below says what happened.
      }
      if (!res.ok || !json || json.ok !== true) {
        const why = json && typeof json.description === "string" ? `: ${json.description}` : "";
        throw new Error(`Telegram answered ${res.status}${why}`);
      }
      return json.result;
    } catch (e) {
      throw new Error(scrub(String((e as Error).message ?? e)));
    }
  }

  async function getBot(): Promise<string | null> {
    if (bot || !token) return bot;
    try {
      const me = obj(await api("getMe", {}, 8000));
      const name = me && str(me.username);
      if (name) bot = `@${name}`;
    } catch (e) {
      error = (e as Error).message;
    }
    return bot;
  }

  function keep(c: TgCall) {
    if (kept.some((k) => k.id === c.id)) return;
    kept = [c, ...kept].sort((a, b) => b.date - a.date).slice(0, KEEP);
    if (file) {
      try {
        mkdirSync(opts.dataDir!, { recursive: true });
        appendFileSync(file, `${JSON.stringify(c)}\n`);
      } catch {
        // The call is still in memory; only a restart would lose it.
      }
    }
  }

  /** One update: ignore what isn't a text message from a person in an allowed group. */
  function ingest(update: unknown) {
    const u = obj(update);
    const m = obj(u?.message) ?? obj(u?.channel_post);
    if (!m) return;
    const chat = obj(m.chat);
    if (!chat || typeof chat.id !== "number") return;
    if (chat.type !== "group" && chat.type !== "supergroup" && chat.type !== "channel") return;
    const chatId = String(chat.id);
    if (allow.size && !allow.has(chatId)) return;
    const from = obj(m.from);
    if (from?.is_bot === true) return;
    const text = typeof m.text === "string" ? m.text : "";
    if (!text.trim() || text.length > MAX_RAW) return;
    if (typeof m.message_id !== "number" || typeof m.date !== "number") return;

    const title = tidyText(str(chat.title) ?? str(chat.username) ?? str(chat.first_name) ?? "Telegram chat").slice(0, 80) || "Telegram chat";
    const g = groups.get(chatId) ?? { title, messages: 0 };
    g.title = title;
    g.messages += 1;
    groups.set(chatId, g);
    lastMessageAt = Math.max(lastMessageAt ?? 0, m.date);

    const read = readAsCall(text);
    if (!read) return;
    const username = str(chat.username);
    const sender = str(from?.username) ?? str(from?.first_name) ?? str(obj(m.sender_chat)?.title) ?? title;
    keep({
      id: `tg-${chatId}-${m.message_id}`,
      chatId,
      chatTitle: title,
      from: from ? { username: str(from.username), first_name: str(from.first_name) } : { first_name: sender },
      date: m.date,
      text: tidyText(text),
      url: username && /^[A-Za-z0-9_]{4,}$/.test(username) ? `https://t.me/${username}/${m.message_id}` : null,
      asset: read.asset,
      direction: read.direction,
      ...(read.signal ? { signal: read.signal } : {}),
    });
  }

  async function pollOnce(timeoutSec = POLL_SECONDS): Promise<number> {
    if (!token) return 0;
    const result = await api(
      "getUpdates",
      { offset, timeout: timeoutSec, allowed_updates: ["message", "channel_post"] },
      (timeoutSec + 10) * 1000,
      abort?.signal,
    );
    const updates = Array.isArray(result) ? result : [];
    for (const u of updates) {
      ingest(u);
      const id = obj(u)?.update_id;
      if (typeof id === "number" && id >= offset) offset = id + 1;
    }
    error = null;
    return updates.length;
  }

  async function loop() {
    let wait = opts.retryMs ?? 2000;
    while (running) {
      try {
        await pollOnce();
        wait = opts.retryMs ?? 2000;
      } catch (e) {
        if (!running) return;
        error = (e as Error).message;
        console.error(`telegram: ${error}`);
        await new Promise((r) => setTimeout(r, wait).unref());
        wait = Math.min(wait * 2 || 0, 60_000);
      }
    }
  }

  return {
    configured: !!token,
    calls: () => kept,
    find: (id) => kept.find((c) => c.id === id),
    async status() {
      const name = token ? await getBot() : null;
      return {
        configured: !!token,
        bot: name,
        groups: [...groups.values()].map((g) => ({ title: g.title, messages: g.messages })),
        lastMessageAt: lastMessageAt ? new Date(lastMessageAt * 1000).toISOString() : null,
        error,
      };
    },
    start() {
      if (!token || running) return;
      running = true;
      abort = new AbortController();
      void getBot();
      void loop();
    },
    stop() {
      running = false;
      abort?.abort();
    },
    pollOnce,
  };
}
