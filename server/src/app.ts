import Fastify from "fastify";
import { runCommand, type Deps } from "./agent.js";

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

  app.get<{ Querystring: { limit?: string } }>("/v1/receipts", async (req) => ({
    receipts: deps.receipts.list(Math.min(200, Number(req.query.limit ?? 50) || 50)),
  }));

  return app;
}
