import Fastify from "fastify";
import { runCommand, type Deps as CommandDeps } from "./agent.js";
import { UserError, type OwnerMethod, type ownerActions } from "./owner.js";
import type { RatesClient } from "./rates.js";

export type Deps = CommandDeps & { owner?: ReturnType<typeof ownerActions>; rates?: RatesClient };

export function buildApp(deps: Deps) {
  const app = Fastify({ logger: false });

  app.addHook("onRequest", async (req, reply) => {
    reply.header("access-control-allow-origin", "*");
    reply.header("access-control-allow-headers", "authorization, content-type");
    if (req.method === "OPTIONS") return reply.code(204).send();
    if (req.url === "/health" || !deps.cfg.apiToken) return;
    if (req.headers.authorization !== `Bearer ${deps.cfg.apiToken}`) return reply.code(401).send({ error: "Missing or wrong token" });
  });

  app.get("/health", async () => ({ ok: true, network: deps.cfg.network, leash: deps.cfg.leash }));

  /** The leash as the chain sees it: agents, caps, today's spend, lists, pending, kill switch. */
  app.get("/v1/state", async () => ({ ...(await deps.chain.state()), explorer: deps.cfg.explorer, contacts: deps.cfg.contacts }));

  /** Run one command. source: "typed" (from the owner) or "pasted" (from someone else). */
  app.post<{ Body: { text?: unknown; source?: unknown } }>("/v1/command", async (req, reply) => {
    const text = typeof req.body?.text === "string" ? req.body.text.trim() : "";
    const source = req.body?.source === "pasted" ? "pasted" : req.body?.source === "typed" ? "typed" : null;
    if (!text || !source) return reply.code(400).send({ error: 'Send {"text": "...", "source": "typed" | "pasted"}' });
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

  return app;
}
