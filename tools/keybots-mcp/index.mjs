#!/usr/bin/env node
// Keybots as an MCP server (stdio, no dependencies): lets an agent like Claude Code
// ask Keybots to pay, through the "Messages you copy" lane. Spend Limits still decides:
// a stranger waits for your Face ID, and anything over the cap is refused on chain.
//
//   KEYBOTS_SERVER  the Keybots server (default: the hosted testnet one)
//   KEYBOTS_TOKEN   its API token
import { createInterface } from "node:readline";

const SERVER = (process.env.KEYBOTS_SERVER ?? "https://13-126-207-245.sslip.io").replace(/\/$/, "");
const TOKEN = process.env.KEYBOTS_TOKEN ?? "";

const TOOLS = [
  {
    name: "keybots_pay",
    description: "Ask Keybots to pay NEAR to someone. It runs in the untrusted lane: Spend Limits checks it on chain, a new receiver waits for the owner's Face ID, and anything over the cap is refused.",
    inputSchema: {
      type: "object",
      properties: {
        to: { type: "string", description: "A NEAR account (name.testnet) or a contact name" },
        amount: { type: "string", description: "NEAR, e.g. \"0.3\"" },
        note: { type: "string", description: "What it's for" },
      },
      required: ["to", "amount"],
    },
  },
  { name: "keybots_status", description: "Keybots' lanes, their limits and spend today, and recent actions.", inputSchema: { type: "object", properties: {} } },
];

async function api(path, body) {
  const r = await fetch(SERVER + path, {
    method: body ? "POST" : "GET",
    headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json", "x-airkey-client": "claude-code" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error ?? `Keybots answered ${r.status}`);
  return j;
}

const near = (y) => (y == null ? "?" : (Number(BigInt(y) / 10n ** 20n) / 1e4).toString());

async function call(name, args = {}) {
  if (name === "keybots_pay") {
    const amount = String(args.amount ?? "").trim();
    const to = String(args.to ?? "").trim();
    if (!/^\d+(\.\d+)?$/.test(amount) || !to) throw new Error("Give `to` and a plain `amount` like 0.3");
    const text = `pay ${to} ${amount}${args.note ? ` for ${String(args.note).slice(0, 120)}` : ""}`;
    const r = await api("/v1/command", { text, source: "pasted", client: "claude-code" });
    return `${r.outcome}: ${r.summary ?? r.message ?? ""}${r.tx ? `\n${r.tx}` : ""}`.trim();
  }
  if (name === "keybots_status") {
    const [s, rs] = await Promise.all([api("/v1/state"), api("/v1/receipts?limit=5")]);
    const lanes = (s.agents ?? []).map((e) => {
      const a = e.agent ?? e;
      return `- ${e.account ?? a.account}: ${a.tier}, ${near(a.per_payment_cap)} a payment, ${near(a.spent_today)} of ${near(a.daily_cap)} NEAR today${a.paused ? " (stopped)" : ""}`;
    });
    const recent = (rs.receipts ?? rs ?? []).slice(0, 5).map((r) => `- ${r.at}: ${r.outcome} · ${r.input?.text ?? ""}${r.input?.client ? ` (from ${r.input.client})` : ""}`);
    return [`Stop everything: ${s.paused ? "on" : "off"} · ${near(s.available)} NEAR in Spend Limits`, "Lanes:", ...lanes, "Recent:", ...recent].join("\n");
  }
  throw new Error(`No tool ${name}`);
}

const send = (m) => process.stdout.write(JSON.stringify(m) + "\n");
createInterface({ input: process.stdin }).on("line", async (line) => {
  let m;
  try { m = JSON.parse(line); } catch { return; }
  if (m.id === undefined) return; // notifications
  const ok = (result) => send({ jsonrpc: "2.0", id: m.id, result });
  if (m.method === "initialize") return ok({ protocolVersion: m.params?.protocolVersion ?? "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "keybots", version: "0.1.0" } });
  if (m.method === "tools/list") return ok({ tools: TOOLS });
  if (m.method === "tools/call") {
    try { return ok({ content: [{ type: "text", text: await call(m.params?.name, m.params?.arguments) }] }); }
    catch (e) { return ok({ content: [{ type: "text", text: String(e.message ?? e) }], isError: true }); }
  }
  if (m.method === "ping") return ok({});
  send({ jsonrpc: "2.0", id: m.id, error: { code: -32601, message: `No method ${m.method}` } });
});
