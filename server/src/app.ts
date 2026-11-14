import { attestations } from "./attest.js";
import Fastify from "fastify";
import { ACT_ACTIONS, ActMoney, ActUnavailable, act, type ActAction } from "./act.js";
import { MONEY_REFUSAL, plainError, readAssistBody, runAssist } from "./assist.js";
import { aiReaders, describe, readCommand, runCommand, type Deps as CommandDeps } from "./agent.js";
import { memoryCalls, readCall, routeCall, type CallStore } from "./calls.js";
import { GifsUnavailable, gifClient, type GifClient } from "./gifs.js";
import { followJson, followPoller, memoryFollows, parseFollow, recordOf, type FollowPoller, type FollowStore, type KolRecord } from "./follows.js";
import { kallClient, type KallClient } from "./kall.js";
import { UserError, type OwnerMethod, type ownerActions } from "./owner.js";
import type { RatesClient } from "./rates.js";
import { toYocto } from "./parse.js";
import { fromUnits, minOut } from "./rhea.js";
import { QuoteError, poolReturnFor, quoter, type OrderKind, type PoolReturn } from "./quote.js";
import { memoryVault, parseVault, type VaultStore } from "./vault.js";
import { TradeError, tradeFlow } from "./trade.js";
import type { TelegramSource } from "./telegram.js";
import { cachedState, renderLeash } from "./leash-page.js";

export type Deps = CommandDeps & {
  owner?: ReturnType<typeof ownerActions>;
  rates?: RatesClient;
  calls?: CallStore;
  /** Rhea's pool view, for the trade panel's quotes (tests pass a fake). */
  poolReturn?: PoolReturn;
  /** The vault the app saves and the keyboard reads. */
  vault?: VaultStore;
  /** The KOLs the owner follows, and what their calls led to. */
  follows?: FollowStore;
  /** Kall Markets' API, where their calls come from. */
  kall?: KallClient;
  /** Telegram calls (telegram.ts): a bot in a group, read-only. Absent or without a token, the feed is Kall's alone. */
  telegram?: TelegramSource;
  /** The same poller index.ts runs every minute, so "check now" and the timer never trade one call twice. */
  followPoller?: FollowPoller;
  /** KLIPY's GIFs, through this server (the key stays here). Tests pass a client with a fake fetch. */
  gifs?: GifClient;
  /** The network the keyboard AI uses (NEAR AI Cloud, OpenAI, Serper). Tests pass a fake. */
  aiFetch?: typeof fetch;
  /** The clock reviews expire by (tests move it). */
  now?: () => number;
};

/**
 * The follow poller for these deps: a followed KOL's call gets the copied
 * call's route (sized to their rules) and runs as a "follow" command.
 */
export function followsFor(deps: Deps): FollowPoller {
  return followPoller({
    follows: deps.follows ?? memoryFollows(),
    kall: deps.kall ?? kallClient(deps.cfg.kallApi),
    autoTrade: deps.cfg.autoTrade,
    route: (text, call, usd) => routeCall(text, call, { intents: deps.intents, chain: deps.chain, tradeAgent: deps.cfg.agents.trade, network: deps.cfg.network, rhea: deps.rhea, usd }),
    run: (command, from) => runCommand(deps, command, "follow", from),
  });
}

export function buildApp(deps: Deps) {
  // The calls book (calls.jsonl in the data dir when index.ts gives one; in memory otherwise).
  const calls = deps.calls ?? memoryCalls();
  /** A token's dollar price on NEAR Intents, or null when it can't be had right now. */
  const priceOf = async (symbol: string): Promise<number | null> => {
    try {
      return (await deps.intents?.price(symbol)) ?? null;
    } catch {
      return null;
    }
  };
  const app = Fastify({ logger: false });

  app.addHook("onRequest", async (req, reply) => {
    reply.header("access-control-allow-origin", "*");
    reply.header("access-control-allow-headers", "authorization, content-type");
    reply.header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS");
    if (req.method === "OPTIONS") return reply.code(204).send();
    // Public: /health, and the Spend Limits page at /limits and /leash (only public chain data and plain receipt lines).
    const path = req.url.split("?")[0];
    if (path === "/health" || path === "/leash" || path === "/limits" || !deps.cfg.apiToken) return;
    if (req.headers.authorization !== `Bearer ${deps.cfg.apiToken}`) return reply.code(401).send({ error: "Missing or wrong token" });
  });

  app.get("/health", async () => ({ ok: true, network: deps.cfg.network, leash: deps.cfg.leash }));

  /** The judge page: Spend Limits live from chain (cached 15 s) and the last decisions, read-only. /leash is the old address. */
  const leashState = cachedState(deps.chain);
  const limitsPage = async (_req: unknown, reply: import("fastify").FastifyReply) => {
    let state = null;
    let readAt = Date.now();
    let error: string | undefined;
    try {
      ({ state, at: readAt } = await leashState());
    } catch (e) {
      error = String((e as Error).message ?? e).slice(0, 120);
    }
    const html = renderLeash({ cfg: deps.cfg, state, readAt, receipts: deps.receipts.list(15), error });
    return reply.header("content-type", "text/html; charset=utf-8").header("cache-control", "public, max-age=15").send(html);
  };
  app.get("/limits", limitsPage);
  app.get("/leash", limitsPage);

  /** The leash as the chain sees it: agents, caps, today's spend, lists, pending, kill switch, and the tokens it holds. */
  app.get("/v1/state", async () => {
    const [state, holdings] = await Promise.all([deps.chain.state(), deps.rhea ? deps.rhea.holdings(deps.cfg.leash).catch(() => []) : []]);
    // `active`: the three agent accounts this server signs for (named, or OutLayer's when that's on).
    return { ...state, explorer: deps.cfg.explorer, contacts: deps.cfg.contacts, holdings, active: deps.cfg.agents };
  });

  /** What swapping `amount` NEAR into a token gets on Rhea right now, before you hold to swap. */
  app.get<{ Querystring: { amount?: string; to?: string } }>("/v1/swap/quote", async (req, reply) => {
    const route = deps.rhea?.route(String(req.query.to ?? ""));
    if (!deps.rhea?.network || !route) return reply.code(404).send({ error: `Keybots can't swap NEAR into ${req.query.to ?? "that"} here` });
    let amountIn: string;
    try {
      amountIn = toYocto(String(req.query.amount ?? ""));
      if (BigInt(amountIn) <= 0n) throw new Error();
    } catch {
      return reply.code(400).send({ error: "Send an amount of NEAR, like 0.1" });
    }
    try {
      const out = await deps.rhea.quote(route, amountIn);
      return { venue: "Rhea", pool: route.pool, from: "NEAR", to: route.symbol, amountIn: req.query.amount, amountOut: fromUnits(out, route.decimals), minAmountOut: fromUnits(minOut(out), route.decimals) };
    } catch (e) {
      return reply.code(502).send({ error: `Rhea didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /**
   * Read a command without running it, for the keyboard's chip: what it is in
   * words, and the exact command to send when you hold. Rules first, an AI
   * only for wording the rules can't read.
   */
  app.post<{ Body: { text?: unknown } }>("/v1/read", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim().slice(0, 500) : "";
    if (!text) return reply.code(400).send({ error: 'Send {"text": "..."}' });
    const read = await readCommand(deps, text);
    const d = describe(read.action);
    if (!d) return { kind: "unknown", reader: read.reader };
    return { ...d, reader: read.reader };
  });

  /** Run one command. source: "typed" (from the owner) or "pasted" (from someone else). */
  app.post<{ Body: { text?: unknown; source?: unknown; callId?: unknown } }>("/v1/command", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim() : "";
    const source = req.body?.source === "pasted" ? "pasted" : req.body?.source === "typed" ? "typed" : null;
    if (!text || !source) return reply.code(400).send({ error: 'Send {"text": "...", "source": "typed" | "pasted"}' });
    // One line per command, with which client sent it (the iOS keyboard or the app).
    const client = String(req.headers["x-airkey-client"] ?? "unknown").slice(0, 20);
    console.log(`${new Date().toISOString()} command from ${client} (${source}): ${JSON.stringify(text.slice(0, 120))}`);
    try {
      const receipt = await runCommand(deps, text, source);
      // A hold on a copied call's chip: the calls book keeps what it came back with.
      if (typeof req.body?.callId === "string") {
        calls.traded(req.body.callId, { at: receipt.at, receiptId: receipt.id, outcome: receipt.outcome, message: receipt.message, tx: receipt.tx });
      }
      return receipt;
    } catch (e) {
      return reply.code(502).send({ error: `NEAR didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /** A token's live price, from NEAR Intents' own list. Unknown or look-alike symbols get 404. */
  app.get<{ Params: { symbol: string } }>("/v1/price/:symbol", async (req, reply) => {
    if (!deps.intents) return reply.code(501).send({ error: "Prices aren't set up on this server" });
    const symbol = req.params.symbol.replace(/^\$/, "").toUpperCase();
    if (!/^[A-Z][A-Z0-9]{1,9}$/.test(symbol)) return reply.code(400).send({ error: "That isn't a token symbol" });
    try {
      const check = await deps.intents.pick(symbol, "to");
      if (!check.verified || !check.token || typeof check.token.price !== "number") {
        return reply.code(404).send({ error: check.verified ? `No price for ${symbol} right now` : check.reason });
      }
      return { symbol, usd: check.token.price, blockchain: check.token.blockchain, assetId: check.token.assetId, source: "NEAR Intents" };
    } catch (e) {
      return reply.code(502).send({ error: `NEAR Intents didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /** Price-triggered orders, newest first. */
  app.get("/v1/orders", async (_req, reply) => {
    if (!deps.orders) return reply.code(501).send({ error: "Orders aren't set up on this server" });
    return { orders: deps.orders.list() };
  });

  /** Stop watching. Only an order that is still waiting can be cancelled. */
  app.delete<{ Params: { id: string } }>("/v1/orders/:id", async (req, reply) => {
    if (!deps.orders) return reply.code(501).send({ error: "Orders aren't set up on this server" });
    const order = deps.orders.list().find((o) => o.id === req.params.id);
    if (!order) return reply.code(404).send({ error: "No such order" });
    if (order.status !== "watching") return reply.code(409).send({ error: `That order is already ${order.status}` });
    return deps.orders.update(order.id, { status: "cancelled" });
  });

  /** "100 usd to inr" for the keyboard: today's rate, nothing stored. */
  app.get<{ Querystring: { amount?: string; from?: string; to?: string } }>("/v1/fx", async (req, reply) => {
    if (!deps.rates) return reply.code(501).send({ error: "Currency rates aren't set up on this server" });
    const amount = Number(req.query.amount);
    const { from = "", to = "" } = req.query;
    if (!Number.isFinite(amount) || amount < 0 || !/^[a-z]{3}$/i.test(from) || !/^[a-z]{3}$/i.test(to)) {
      return reply.code(400).send({ error: "Send ?amount=100&from=usd&to=inr" });
    }
    try {
      const c = await deps.rates.convert(amount, from, to);
      if (!c) return reply.code(404).send({ error: `I don't have a rate for ${from.toUpperCase()} to ${to.toUpperCase()}` });
      return { amount, from: from.toUpperCase(), to: to.toUpperCase(), value: c.value, rate: c.rate, date: c.date };
    } catch (e) {
      return reply.code(502).send({ error: `Rates didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /** Every symbol NEAR Intents lists, so the keyboard only offers trades in real tokens. */
  app.get("/v1/tokens", async (_req, reply) => {
    if (!deps.intents) return reply.code(501).send({ error: "Tokens aren't set up on this server" });
    try {
      const list = await deps.intents.tokens();
      const symbols = new Set(list.map((t) => t.symbol.toUpperCase()));
      if (symbols.has("WNEAR")) symbols.add("NEAR"); // what people type
      return { symbols: [...symbols].sort(), source: "NEAR Intents" };
    } catch (e) {
      return reply.code(502).send({ error: `NEAR Intents didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  app.get<{ Querystring: { limit?: string } }>("/v1/receipts", async (req) => ({
    receipts: deps.receipts.list(Math.min(200, Number(req.query.limit ?? 50) || 50)),
  }));

  /** Owner actions: the server builds the transaction, the phone signs its hash, the server relays it. */
  app.post<{ Body: { method?: string; args?: Record<string, unknown>; publicKey?: string } }>("/v1/owner/prepare", async (req, reply) => {
    const { method, args = {}, publicKey } = req.body ?? {};
    if (!deps.owner) return reply.code(501).send({ error: "Owner actions aren't set up on this server" });
    if (!method || !publicKey) return reply.code(400).send({ error: 'Send {"method", "args", "publicKey"}' });
    try {
      return await deps.owner.prepare(method as OwnerMethod, args, publicKey);
    } catch (e) {
      return reply.code(e instanceof UserError ? 400 : 502).send({ error: (e as Error).message });
    }
  });

  app.post<{ Body: { tx?: string; signature?: string } }>("/v1/owner/submit", async (req, reply) => {
    const { tx, signature } = req.body ?? {};
    if (!deps.owner) return reply.code(501).send({ error: "Owner actions aren't set up on this server" });
    if (!tx || !signature) return reply.code(400).send({ error: 'Send {"tx", "signature"}' });
    try {
      return await deps.owner.submit(tx, signature);
    } catch (e) {
      return reply.code(e instanceof UserError ? 400 : 502).send({ error: (e as Error).message.slice(0, 300) });
    }
  });

  /**
   * The keyboard's AI bar: rewrite, reply, translate, tone or ask, on the
   * text in the field. Only the text comes back, with who answered; the
   * keyboard never puts it in by itself.
   */
  app.post<{ Body: { text?: unknown; action?: unknown; tone?: unknown; language?: unknown } }>("/v1/act", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim() : "";
    const action = req.body?.action as ActAction;
    if (!text || !ACT_ACTIONS.includes(action)) {
      return reply.code(400).send({ error: `Send {"text": "...", "action": "${ACT_ACTIONS.join('" | "')}"}` });
    }
    const tone = typeof req.body?.tone === "string" ? req.body.tone : undefined;
    const language = typeof req.body?.language === "string" ? req.body.language : undefined;
    try {
      return await act({ text, action, tone, language }, aiReaders(deps.cfg), deps.aiFetch);
    } catch (e) {
      if (e instanceof ActMoney) return reply.code(409).send({ error: MONEY_REFUSAL, money: true });
      if (e instanceof ActUnavailable) return reply.code(503).send({ error: e.message });
      return reply.code(502).send({ error: `The AI didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /**
   * The keyboard's AI, streamed as server-sent events: fix, shorter, warmer,
   * formal, reply, translate, ask or search on `text`. Events: chunk {t},
   * option {id, label, text}, result {id, title, url, site, snippet}, then
   * done {task, text, options?, results?, receipt, note?} or error {error}.
   * Money is refused (409) before any AI sees it.
   */
  // NEAR AI Cloud's hardware attestation as this server last checked it (every ten minutes): what passed, failed or was unavailable.
  app.get("/v1/ai/attestation", async (_req, reply) => {
    const r = attestations.get(deps.cfg.nearAi.model);
    if (!r) return reply.code(503).send({ error: "The hardware attestation hasn't been checked yet. Try again in a minute.", status: "not checked" });
    return r;
  });

  app.post("/v1/assist", async (req, reply) => {
    const gate = readAssistBody(req.body);
    if (!gate.ok) return reply.code(gate.status).send(gate.body);
    const readers = aiReaders(deps.cfg);
    if (readers.length === 0) return reply.code(503).send({ error: "AI isn't set up on this server." });
    if (gate.req.task === "search" && !deps.cfg.serperKey) return reply.code(503).send({ error: "Search isn't set up on this server." });

    reply.hijack();
    const res = reply.raw;
    res.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      "x-accel-buffering": "no",
      "access-control-allow-origin": "*",
    });
    const stop = new AbortController();
    res.on("close", () => {
      if (!res.writableEnded) stop.abort();
    });
    const send = (event: string, data: object) => {
      if (!res.writableEnded && !res.destroyed) res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };
    try {
      send("done", await runAssist(gate.req, { readers, serperKey: deps.cfg.serperKey, fetchImpl: deps.aiFetch, signal: stop.signal }, send));
    } catch (e) {
      if (!stop.signal.aborted) console.log(`${new Date().toISOString()} assist ${gate.req.task} failed: ${String((e as Error).message ?? e).slice(0, 160)}`);
      send("error", { error: plainError(e) });
    }
    res.end();
  });

  /**
   * A copied crypto call: what it says, and the one small trade the keyboard
   * may offer for it. Runs nothing; the hold sends `route.command` as typed.
   */
  app.post<{ Body: { text?: unknown } }>("/v1/call", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim().slice(0, 2000) : "";
    if (!text) return reply.code(400).send({ error: 'Send {"text": "..."}' });
    const call = readCall(text);
    const route = await routeCall(text, call, { intents: deps.intents, chain: deps.chain, tradeAgent: deps.cfg.agents.trade, network: deps.cfg.network, rhea: deps.rhea });
    if (!call.isCall) return { call, route };
    // Every call that was checked goes in the calls book, with the token's price at that moment.
    let priceThen = route.status === "available" ? (route.token.price ?? null) : null;
    if (priceThen === null && call.asset) priceThen = await priceOf(call.asset);
    const record = calls.check(text, call, route, priceThen);
    return { call, route, id: record.id };
  });

  /**
   * The calls book, newest first: every copied call that was checked, the
   * trade its hold ran (or null), and the token's price now beside its price
   * at the call.
   */
  app.get<{ Querystring: { limit?: string } }>("/v1/calls", async (req) => {
    const list = calls.list(Math.min(200, Number(req.query.limit ?? 50) || 50));
    const now = new Map<string, number | null>();
    const assets = [...new Set(list.map((c) => c.asset).filter((a): a is string => Boolean(a)))];
    await Promise.race([
      Promise.all(assets.map(async (a) => now.set(a, await priceOf(a)))),
      new Promise((r) => setTimeout(r, 1500)), // A slow price list doesn't hold the book up.
    ]);
    return { calls: list.map((c) => ({ ...c, priceNow: (c.asset && now.get(c.asset)) ?? null })) };
  });

  /** Put a call away without trading it. */
  app.post<{ Params: { id: string } }>("/v1/calls/:id/dismiss", async (req, reply) => {
    const record = calls.dismiss(req.params.id);
    return record ?? reply.code(404).send({ error: "No such call" });
  });

  // --- Trade panel (quote.ts) ---
  const quotes = quoter({ cfg: deps.cfg, chain: deps.chain, intents: deps.intents, rhea: deps.rhea, poolReturn: deps.poolReturn ?? poolReturnFor(deps.cfg.network, deps.cfg.rpc) });

  /**
   * Everything the trade panel shows for one swap, before the hold: what it
   * gets, the least it may get, the route, the fee, the caps and the balance,
   * and the exact command the hold sends. `order` (limit | stop | take) with
   * `trigger` makes it a price-triggered order instead. Sends nothing.
   */
  app.get<{ Querystring: { from?: string; to?: string; amount?: string; order?: string; trigger?: string } }>("/v1/quote", async (req, reply) => {
    const { from = "", to = "", amount = "", order, trigger } = req.query;
    if (order !== undefined && !["limit", "stop", "take"].includes(order)) return reply.code(400).send({ error: "order is limit, stop or take" });
    try {
      return await quotes.quote({ from, to, amount, order: order as OrderKind | undefined, trigger });
    } catch (e) {
      if (e instanceof QuoteError) return reply.code(e.status).send({ error: e.message });
      return reply.code(502).send({ error: `The quote didn't come back: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /** The token picker: symbol, price and what the leash holds. */
  app.get("/v1/tokens/list", async (_req, reply) => {
    try {
      return await quotes.tokens();
    } catch (e) {
      if (e instanceof QuoteError) return reply.code(e.status).send({ error: e.message });
      return reply.code(502).send({ error: `NEAR Intents didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  // The vault, shared through the server because free signing has no App Group.
  const vault = deps.vault ?? memoryVault();
  app.get("/v1/vault", async () => ({ items: vault.list() }));
  app.put("/v1/vault", async (req, reply) => {
    try {
      const items = parseVault(req.body);
      vault.save(items);
      return { items };
    } catch (e) {
      return reply.code(400).send({ error: (e as Error).message });
    }
  });

  // --- Following KOLs (follows.ts, kall.ts) ---
  const follows = deps.follows ?? memoryFollows();
  const kall = deps.kall ?? kallClient(deps.cfg.kallApi);
  const poller = deps.followPoller ?? followsFor({ ...deps, follows, kall });
  /** A caller's record from Kall, or null when Kall can't say right now (a slow answer doesn't hold the list up). */
  const recordFor = (handle: string): Promise<KolRecord | null> =>
    Promise.race([
      kall.caller(handle).then(recordOf).catch(() => null),
      new Promise<null>((r) => setTimeout(() => r(null), 1500)),
    ]);
  const kallDown = (e: unknown) => `Kall didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}`;

  /** Who the owner follows, with their rules and record, and the newest 50 trades their calls led to. */
  app.get("/v1/follows", async () => {
    const list = follows.list();
    const records = await Promise.all(list.map((f) => recordFor(f.handle)));
    return { follows: list.map((f, i) => followJson(f, records[i] ?? null)), trades: follows.trades(50) };
  });

  /** Follow a handle, or change the rules for one. Turning auto back on lifts a pause. */
  app.post("/v1/follows", async (req, reply) => {
    const parsed = parseFollow(req.body);
    if ("error" in parsed) return reply.code(400).send({ error: parsed.error });
    const f = follows.upsert(parsed.handle, parsed.rules);
    return followJson(f, await recordFor(f.handle));
  });

  app.delete<{ Params: { handle: string } }>("/v1/follows/:handle", async (req, reply) => {
    if (!follows.remove(req.params.handle)) return reply.code(404).send({ error: "You don't follow them" });
    return { ok: true };
  });

  /** Kall's tracked callers and their records, to suggest who to follow. */
  app.get("/v1/kols", async (_req, reply) => {
    try {
      const feed = await kall.feed();
      return {
        callers: feed.callers.map((c) => ({
          handle: c.handle,
          focus: c.focus,
          hits: c.hits,
          misses: Math.max(0, c.settled - c.hits),
          open: c.open,
          // Kall gives the median return; it stands in for the average here.
          avgReturnBps: c.medianBps,
        })),
      };
    } catch (e) {
      return reply.code(502).send({ error: kallDown(e) });
    }
  });

  /**
   * Check a followed handle now. `latest: true` takes their newest call even
   * if it's older than the follow (the owner asked for it); the same rules
   * and the same auto-trading switch still apply.
   */
  app.post<{ Params: { handle: string }; Body: { latest?: unknown } }>("/v1/follows/:handle/check", async (req, reply) => {
    if (!follows.get(req.params.handle)) return reply.code(404).send({ error: "You don't follow them" });
    try {
      return { trades: await poller.poll(req.params.handle, { latest: req.body?.latest === true }) };
    } catch (e) {
      return reply.code(502).send({ error: kallDown(e) });
    }
  });

  // --- A KOL's call: feed -> review -> confirm -> the leash decides -> receipt (trade.ts) ---
  const trade = tradeFlow({ ...deps, kall, telegram: deps.telegram, now: deps.now });

  /** Kall's and Telegram's newest spot calls together (up to 10), or three labelled samples when there are none. */
  app.get("/v1/kol/feed", async () => trade.feed());

  /** Is the Telegram bot set up and seeing messages? The bot's name and which groups it has read; never the token or message text. */
  app.get("/v1/telegram/status", async () =>
    deps.telegram ? deps.telegram.status() : { configured: false, bot: null, groups: [], lastMessageAt: null, error: null },
  );

  /** The exact trade a call would run, for 30 seconds. Sends nothing. */
  app.post<{ Body: { callId?: unknown; text?: unknown; usd?: unknown } }>("/v1/trade/review", async (req, reply) => {
    try {
      return await trade.review(req.body ?? {});
    } catch (e) {
      if (e instanceof TradeError) return reply.code(e.status).send({ error: e.message, ...e.extra });
      return reply.code(502).send({ error: `The review didn't come back: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
  });

  /** Run a review once, through the Trading Agent. The leash decides; a repeat gets the same receipt. */
  app.post<{ Body: { reviewId?: unknown } }>("/v1/trade/confirm", async (req, reply) => {
    const { code, body } = await trade.confirm(req.body?.reviewId);
    if (code === 200 && "status" in body) {
      const client = String(req.headers["x-airkey-client"] ?? "unknown").slice(0, 20);
      if (!("repeat" in body)) console.log(`${new Date().toISOString()} reviewed trade from ${client}: ${body.status}`);
    }
    return reply.code(code).send(body);
  });

  // --- GIFs (gifs.ts): KLIPY through this server, so its key never reaches the phone ---
  const gifs = deps.gifs ?? gifClient();
  /** A page of GIFs for the emoji board: trending (no q) or a search. */
  app.get<{ Querystring: { q?: string; page?: string } }>("/v1/gifs", async (req, reply) => {
    if (!gifs.ready) return reply.code(503).send({ error: "GIFs aren't set up on this server" });
    const q = String(req.query.q ?? "").trim().slice(0, 80);
    const page = Math.max(1, Math.min(50, Math.floor(Number(req.query.page ?? 1)) || 1));
    try {
      return await gifs.page(q, page);
    } catch (e) {
      if (e instanceof GifsUnavailable) return reply.code(503).send({ error: e.message });
      // A fixed message: KLIPY's URL holds the key, so nothing from the failure is passed on.
      return reply.code(502).send({ error: "KLIPY didn't answer. Try again in a moment." });
    }
  });

  return app;
}
