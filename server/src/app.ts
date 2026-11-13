import Fastify from "fastify";
import { ACT_ACTIONS, ActUnavailable, act, type ActAction } from "./act.js";
import { aiReaders, describe, readCommand, runCommand, type Deps as CommandDeps } from "./agent.js";
import { readCall, routeCall } from "./calls.js";
import { UserError, type OwnerMethod, type ownerActions } from "./owner.js";
import type { RatesClient } from "./rates.js";
import { toYocto } from "./parse.js";
import { fromUnits, minOut } from "./rhea.js";
import { QuoteError, poolReturnFor, quoter, type OrderKind, type PoolReturn } from "./quote.js";

export type Deps = CommandDeps & { owner?: ReturnType<typeof ownerActions>; rates?: RatesClient; /** Rhea's pool view, for the trade panel's quotes (tests pass a fake). */ poolReturn?: PoolReturn };

export function buildApp(deps: Deps) {
  const app = Fastify({ logger: false });

  app.addHook("onRequest", async (req, reply) => {
    reply.header("access-control-allow-origin", "*");
    reply.header("access-control-allow-headers", "authorization, content-type");
    reply.header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS");
    if (req.method === "OPTIONS") return reply.code(204).send();
    if (req.url === "/health" || !deps.cfg.apiToken) return;
    if (req.headers.authorization !== `Bearer ${deps.cfg.apiToken}`) return reply.code(401).send({ error: "Missing or wrong token" });
  });

  app.get("/health", async () => ({ ok: true, network: deps.cfg.network, leash: deps.cfg.leash }));

  /** The leash as the chain sees it: agents, caps, today's spend, lists, pending, kill switch, and the tokens it holds. */
  app.get("/v1/state", async () => {
    const [state, holdings] = await Promise.all([deps.chain.state(), deps.rhea ? deps.rhea.holdings(deps.cfg.leash).catch(() => []) : []]);
    // `active`: the three agent accounts this server signs for (named, or OutLayer's when that's on).
    return { ...state, explorer: deps.cfg.explorer, contacts: deps.cfg.contacts, holdings, active: deps.cfg.agents };
  });

  /** What swapping `amount` NEAR into a token gets on Rhea right now, before you hold to swap. */
  app.get<{ Querystring: { amount?: string; to?: string } }>("/v1/swap/quote", async (req, reply) => {
    const route = deps.rhea?.route(String(req.query.to ?? ""));
    if (!deps.rhea?.network || !route) return reply.code(404).send({ error: `AIRKEY can't swap NEAR into ${req.query.to ?? "that"} here` });
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
  app.post<{ Body: { text?: unknown; source?: unknown } }>("/v1/command", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim() : "";
    const source = req.body?.source === "pasted" ? "pasted" : req.body?.source === "typed" ? "typed" : null;
    if (!text || !source) return reply.code(400).send({ error: 'Send {"text": "...", "source": "typed" | "pasted"}' });
    // One line per command, with which client sent it (the iOS keyboard or the app).
    const client = String(req.headers["x-airkey-client"] ?? "unknown").slice(0, 20);
    console.log(`${new Date().toISOString()} command from ${client} (${source}): ${JSON.stringify(text.slice(0, 120))}`);
    try {
      return await runCommand(deps, text, source);
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
      return await act({ text, action, tone, language }, aiReaders(deps.cfg));
    } catch (e) {
      if (e instanceof ActUnavailable) return reply.code(503).send({ error: e.message });
      return reply.code(502).send({ error: `The AI didn't answer: ${String((e as Error).message ?? e).slice(0, 200)}` });
    }
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
    return { call, route };
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

  return app;
}
