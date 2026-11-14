// GET /leash: a public, read-only page for anyone without the phone. Everything
// on it is public chain data, plus one plain line per recent receipt with only
// public fields (time, agent, outcome, transaction link). No auth, no JS.
import { plainSummary } from "./agent.js";
import type { Config } from "./config.js";
import { agentName, near, spentToday } from "./dryrun.js";
import type { Chain, LeashState } from "./near.js";
import type { Receipt, ReceiptStore } from "./receipts.js";

export const REPO = "https://github.com/harshalbhangale/near-hack";
export const CACHE_MS = 15_000;

interface Pending {
  id: number;
  agent: string;
  receiver: string;
  amount: string;
  memo?: string | null;
  reason: string;
  created_at_ns: number | string;
}

/** The leash's state, read at most once per `CACHE_MS`. */
export function cachedState(chain: Pick<Chain, "state">, ms = CACHE_MS, now = () => Date.now()) {
  let hit: { at: number; state: LeashState } | null = null;
  return async (): Promise<{ state: LeashState; at: number }> => {
    if (hit && now() - hit.at < ms) return hit;
    const state = await chain.state();
    hit = { at: now(), state };
    return hit;
  };
}

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const short = (a: string) => (/^[0-9a-f]{64}$/.test(a) ? `${a.slice(0, 6)}…${a.slice(-4)}` : a);

/** One plain line for a receipt, from its public fields only. */
export function publicLine(r: Receipt, cfg: Config): { at: string; agent: string; line: string; tx?: string; outcome: Receipt["outcome"]; source: string } {
  const generic: Record<Receipt["outcome"], string> = {
    paid: "Paid",
    swapped: "Swapped",
    approval: "Waiting for the owner to approve",
    blocked: "Blocked",
    quoted: "Quoted a swap. Nothing sent",
    watching: "Watching a price",
    "not-sent": "Not sent",
  };
  const account = r.agent?.account ?? r.swap?.leash?.agent;
  return {
    at: r.at,
    agent: account ? agentName(cfg, account) : "Server",
    line: plainSummary(r, cfg.contacts) ?? generic[r.outcome] ?? "Not sent",
    tx: r.tx?.url,
    outcome: r.outcome,
    source: r.input.source === "pasted" ? "pasted" : r.input.source === "follow" ? "followed call" : "typed",
  };
}

/** The server's agents by name; an implicit (64-hex) account is one whose key OutLayer keeps. */
function nameOf(cfg: Config, account: string): string {
  const n = agentName(cfg, account);
  return n === "Agent" && /^[0-9a-f]{64}$/.test(account) ? "OutLayer agent" : n;
}

function role(cfg: Config, account: string, tier: string): string {
  if (account === cfg.agents.trade) return "Swaps, from what the owner types";
  return tier === "untrusted" ? "Reads other people's messages" : "Acts on what the owner types";
}

const RULES: [string, string][] = [
  ["R1", "Stop everything: one switch the owner holds turns every agent off."],
  ["R3", "The blocked list: no agent can pay an account on it."],
  ["R4", "A per-payment limit for each agent."],
  ["R5", "A daily limit for each agent."],
  ["R6", "An agent reading someone else's message can only pay allowed accounts; anything else waits for the owner."],
  ["R7", "Anything new or odd waits for the owner's Face ID."],
  ["R0", "Nothing leaves that the leash doesn't hold."],
  ["R8", "Tokens the leash holds can only be sold within the owner's per-token rule."],
];

export function renderLeash(opts: {
  cfg: Config;
  state: LeashState | null;
  readAt: number;
  receipts: Receipt[];
  error?: string;
  now?: number;
}): string {
  const { cfg, state } = opts;
  const now = opts.now ?? Date.now();
  const x = cfg.explorer;
  const acct = (a: string) => `<a href="${esc(`${x}/address/${a}`)}">${esc(short(a))}</a>`;
  const time = (iso: string | number) => new Date(iso).toISOString().replace("T", " ").slice(0, 16) + " UTC";

  let chain = `<p class="muted">Couldn't read the chain right now${opts.error ? `: ${esc(opts.error)}` : ""}. Try again in a moment.</p>`;
  if (state) {
    // The server's own agents first (Pay, Inbox, Trading), then the rest.
    const order = [cfg.agents.trusted, cfg.agents.untrusted, cfg.agents.trade];
    const rank = (a: string) => (order.includes(a) ? order.indexOf(a) : order.length);
    const agents = [...state.agents]
      .sort((a, b) => rank(a.account) - rank(b.account))
      .map(({ account, agent: a }) => {
        const spent = spentToday(a, now);
        const daily = BigInt(a.daily_cap);
        const pct = daily > 0n ? Number((spent * 100n) / daily) : 0;
        return `<tr>
  <td><div class="name">${esc(nameOf(cfg, account))}</div><div class="sub">${acct(account)}</div></td>
  <td>${esc(role(cfg, account, a.tier))}<div class="sub">${a.tier === "untrusted" ? "untrusted" : "trusted"}</div></td>
  <td class="num">${near(a.per_payment_cap)}</td>
  <td class="num">${near(spent)} <span class="muted">of</span> ${near(daily)}<div class="bar"><i style="width:${Math.min(100, pct)}%"></i></div></td>
</tr>`;
      })
      .join("");
    const blocked = state.blocklist.length
      ? state.blocklist.map((b) => `<li>${acct(b.account)}<div class="sub">${esc(b.reason)}</div></li>`).join("")
      : `<li class="muted">No one</li>`;
    const allowed = state.allowlist.length ? state.allowlist.map((a) => `<li>${acct(a)}</li>`).join("") : `<li class="muted">No one</li>`;
    const pending = (state.pending as Pending[])
      .map(
        (p) => `<li><span class="num">${near(p.amount)} NEAR</span> to ${acct(p.receiver)} <span class="muted">from the ${esc(agentName(cfg, p.agent))}</span><div class="sub">${esc(p.reason)}${p.memo ? ` · “${esc(p.memo)}”` : ""}</div></li>`,
      )
      .join("");
    chain = `
<section class="status">
  <div><div class="k">Leash</div><div class="v">${acct(state.leash)}</div></div>
  <div><div class="k">NEAR held</div><div class="v big num">${near(state.available, 2, 2)}</div></div>
  <div><div class="k">Stop everything</div><div class="v big ${state.paused ? "on" : "off"}">${state.paused ? "On: every agent is stopped" : "Off"}</div></div>
  <div><div class="k">Owner</div><div class="v">${acct(state.owner)}</div></div>
</section>

<h2>Agents</h2>
<table>
  <thead><tr><th>Agent</th><th>Role</th><th class="num">Per payment</th><th class="num">Spent today</th></tr></thead>
  <tbody>${agents}</tbody>
</table>
<p class="muted small">In NEAR. Each agent holds only a key that can call the leash; the owner's key never leaves the phone.</p>

<div class="cols">
  <section><h2>Blocked</h2><ul>${blocked}</ul></section>
  <section><h2>Allowed</h2><ul>${allowed}</ul></section>
</div>

<h2>Waiting for the owner</h2>
<ul>${pending || `<li class="muted">Nothing waiting</li>`}</ul>`;
  }

  const decisions = opts.receipts.map((r) => publicLine(r, cfg));
  const rows = decisions.length
    ? decisions
        .map(
          (d) => `<li class="d ${esc(d.outcome)}">
  <span class="dot"></span>
  <div class="line">${esc(d.line)}<div class="sub">${esc(time(d.at))} · ${esc(d.agent)} · ${esc(d.source)}${d.tx ? ` · <a href="${esc(d.tx)}">transaction</a>` : ""}</div></div>
</li>`,
        )
        .join("")
    : `<li class="muted">No decisions on this server yet</li>`;

  const rules = RULES.map(([id, text]) => `<li><span class="rule">${id}</span>${esc(text)}</li>`).join("");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AIRKEY leash</title>
<meta name="description" content="The AIRKEY leash on NEAR ${esc(cfg.network)}, live from chain.">
<style>
  :root { --bg:#0B0B0C; --fg:#EDEDE8; --muted:#8A8A85; --line:#1F1F21; --card:#121214; --lime:#C6F45B; --red:#FF6B5E; --amber:#F2C14E; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif; -webkit-font-smoothing:antialiased; }
  main { max-width:860px; margin:0 auto; padding:48px 20px 64px; }
  a { color:var(--fg); text-decoration:underline; text-decoration-color:#444; text-underline-offset:3px; }
  a:hover { text-decoration-color:var(--lime); }
  h1 { font-size:28px; letter-spacing:-0.02em; margin:0 0 8px; font-weight:650; }
  h1 em { font-style:normal; color:var(--lime); }
  h2 { font-size:13px; text-transform:uppercase; letter-spacing:.08em; color:var(--muted); font-weight:600; margin:40px 0 12px; }
  .lede { color:var(--muted); max-width:640px; margin:0 0 6px; }
  .muted { color:var(--muted); }
  .small { font-size:13px; }
  .sub { color:var(--muted); font-size:13px; margin-top:2px; overflow-wrap:anywhere; }
  .num { font-variant-numeric: tabular-nums; }
  .status { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:1px; background:var(--line); border:1px solid var(--line); border-radius:14px; overflow:hidden; margin-top:32px; }
  .status > div { background:var(--card); padding:16px; }
  .k { font-size:12px; color:var(--muted); margin-bottom:4px; }
  .v { font-size:15px; overflow-wrap:anywhere; }
  .v.big { font-size:22px; font-weight:600; }
  .v.off { color:var(--lime); }
  .v.on { color:var(--red); }
  table { width:100%; border-collapse:collapse; }
  th { text-align:left; font-weight:500; color:var(--muted); font-size:12px; padding:0 12px 8px 0; border-bottom:1px solid var(--line); }
  td { padding:14px 12px 14px 0; border-bottom:1px solid var(--line); vertical-align:top; }
  th.num, td.num { text-align:right; padding-right:0; white-space:nowrap; }
  .name { font-weight:600; }
  .bar { height:3px; background:var(--line); border-radius:2px; margin-top:8px; overflow:hidden; }
  .bar i { display:block; height:100%; background:var(--lime); }
  ul { list-style:none; margin:0; padding:0; }
  li { padding:12px 0; border-bottom:1px solid var(--line); }
  .cols { display:grid; grid-template-columns:1fr 1fr; gap:32px; }
  .d { display:flex; gap:12px; align-items:flex-start; }
  .dot { width:8px; height:8px; border-radius:50%; margin-top:8px; flex:none; background:var(--muted); }
  .d.paid .dot, .d.swapped .dot { background:var(--lime); }
  .d.blocked .dot { background:var(--red); }
  .d.approval .dot { background:var(--amber); }
  .rule { display:inline-block; width:34px; color:#5A5A57; font-size:12px; font-variant-numeric:tabular-nums; }
  .rules li { padding:8px 0; color:#C9C9C4; }
  footer { margin-top:48px; color:var(--muted); font-size:13px; }
  @media (min-width:760px) { .status { grid-template-columns:1.7fr 1fr 1fr 1.5fr; } }
  @media (max-width:640px) {
    main { padding:32px 16px 48px; }
    .cols { grid-template-columns:1fr; gap:0; }
    th:nth-child(2), td:nth-child(2) { display:none; }
  }
</style>
</head>
<body>
<main>
<h1>AIRKEY: AI agents in your keyboard. <em>NEAR is the leash.</em></h1>
<p class="lede">Agents that move money from your keyboard can only do it through a NEAR contract that holds the money and checks every payment against the owner's rules: limits, a blocked list, an allowed list, and the owner's approval for anything new.</p>
<p class="small muted">Live from NEAR ${esc(cfg.network)} · <a href="${REPO}">Code on GitHub</a></p>
${chain}

<h2>Recent decisions</h2>
<ul>${rows}</ul>

<h2>How the leash decides</h2>
<ul class="rules">${rules}</ul>

<footer>Read from chain at ${esc(time(opts.readAt))}, at most every 15 seconds. This page only reads; it can't move anything.</footer>
</main>
</body>
</html>`;
}
