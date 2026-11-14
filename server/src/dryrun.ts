// A dry run of one command against the leash's live state: read the words with
// the same rules the server uses, pick the agent that would act, and apply the
// leash's rules in the contract's own order (RULES.md). Read-only: it uses view
// calls and quotes, never a key, and sends nothing.
import { judge } from "./checks.js";
import type { Config } from "./config.js";
import type { IntentsClient } from "./intents.js";
import type { AgentView, AccountFacts, LeashState } from "./near.js";
import { parse, resolveReceiver, toYocto, type Action } from "./parse.js";
import { fromUnits, type RheaClient } from "./rhea.js";

export interface DryRunDeps {
  cfg: Config;
  /** Only the reads: the leash's state and an account's facts. */
  chain: { state(): Promise<LeashState>; facts(account: string): Promise<AccountFacts> };
  intents?: Pick<IntentsClient, "pick" | "quote">;
  rhea?: Pick<RheaClient, "route" | "quote" | "network">;
}

export type Outcome = "pay" | "swap" | "wait" | "blocked" | "unreadable";

export interface DryRun {
  outcome: Outcome;
  /** Label, value: printed as two columns. */
  lines: [string, string][];
}

const YOCTO = 10n ** 24n;

/** yoctoNEAR -> "1.2", "0.5", "0.295"; at least `min` decimals, at most 4. */
export function near(yocto: string | bigint, min = 1, max = 4): string {
  const y = BigInt(yocto);
  const whole = y / YOCTO;
  let frac = ((y % YOCTO) * 10_000n / YOCTO).toString().padStart(4, "0").slice(0, max).replace(/0+$/, "");
  if (frac.length < min) frac = frac.padEnd(min, "0");
  return frac ? `${whole}.${frac}` : `${whole}`;
}

/** What people call each of the server's agents. */
export function agentName(cfg: Config, account: string): string {
  if (account === cfg.agents.trusted) return "Pay Agent";
  if (account === cfg.agents.untrusted) return "Inbox Agent";
  if (account === cfg.agents.trade) return "Trading Agent";
  return "Agent";
}

export const FOOTER = "Dry run: nothing was sent. The contract makes this decision on chain when the agent sends it; see the transactions in docs/DEMO.md.";

export async function dryRun(deps: DryRunDeps, text: string, opts: { pasted?: boolean } = {}): Promise<DryRun> {
  const { cfg } = deps;
  const lines: [string, string][] = [[opts.pasted ? "You pasted" : "You typed", text]];
  const finish = (outcome: Outcome, verdict: string, why?: string, extra: [string, string][] = []): DryRun => {
    lines.push(["Verdict", verdict]);
    if (why) lines.push(["Why", why]);
    lines.push(...extra);
    return { outcome, lines };
  };

  const action: Action = parse(text);
  if (action.kind === "unknown" || action.kind === "watch") {
    const why =
      action.kind === "watch"
        ? "orders that wait for a price run later, as the owner's own words; try the trade on its own"
        : "the rules found no payment or swap in it; the app would ask NEAR AI Cloud to read it, this dry run uses the rules only";
    return finish("unreadable", "Nothing to check", why);
  }

  // Which agent: what you type is trusted, what you paste is not, swaps go to the Trading Agent.
  const state = await deps.chain.state();
  const isSwap = action.kind === "swap";
  const agentId = isSwap
    ? state.agents.some((a) => a.account === cfg.agents.trade)
      ? cfg.agents.trade
      : cfg.agents.trusted
    : opts.pasted
      ? cfg.agents.untrusted
      : cfg.agents.trusted;
  const agent = state.agents.find((a) => a.account === agentId)?.agent;
  const tier = agent?.tier ?? (opts.pasted ? "untrusted" : "trusted");
  lines.push(["Agent", `${agentName(cfg, agentId)} (${agentId}), ${tier}`]);
  lines.push(["Spend Limits", `${state.leash}: ${near(state.available, 2, 2)} NEAR, Stop everything ${state.paused ? "on" : "off"}`]);

  if (isSwap && opts.pasted) {
    return finish("blocked", "Would be blocked: trades only run from what you type, never from a copied message", "the server stops it before asking Spend Limits");
  }

  // What is being sent where, and what it's worth in NEAR.
  let receiver: string;
  let shown: string;
  let amount: bigint;
  const extra: [string, string][] = [];
  if (action.kind === "pay") {
    const to = resolveReceiver(action.receiver, cfg.contacts, cfg.network);
    if ("error" in to) return finish("unreadable", "Would not be sent", to.error);
    receiver = to.account;
    shown = to.account;
    try {
      amount = BigInt(toYocto(action.amountNear));
    } catch {
      return finish("unreadable", "Would not be sent", `${action.amountNear} isn't an amount of NEAR`);
    }
  } else {
    const q = await swapValue(deps, action);
    if ("error" in q) return finish("unreadable", "Would not be sent", q.error);
    amount = q.value;
    receiver = q.venue;
    shown = q.venue;
    extra.push(...q.quotes);
  }

  // The contract's order: Stop everything, registered agent, blocked list,
  // per-payment cap, daily cap, waiting for the owner, enough NEAR.
  if (state.paused) return finish("blocked", "Would be blocked: Stop everything is on", "the owner turned it on; no agent can move anything", extra);
  if (!agent) return finish("blocked", `Would be refused: ${agentId} isn't one of Spend Limits' agents`, undefined, extra);
  if (amount <= 0n) return finish("unreadable", "Would not be sent", "the amount must be more than zero", extra);
  const blocked = state.blocklist.find((b) => b.account === receiver);
  if (blocked) {
    return finish("blocked", `Would be blocked: ${shown} is on the blocked list (checked on chain by the contract)`, plainReason(blocked.reason), extra);
  }
  const per = BigInt(agent.per_payment_cap);
  const kind = isSwap ? "per trade" : "per payment";
  if (amount > per) {
    return finish("blocked", `Would be blocked: ${near(amount)} NEAR is over the ${near(per)} NEAR ${kind} limit`, `the ${agentName(cfg, agentId)} may move at most ${near(per)} NEAR at a time`, extra);
  }
  const spent = spentToday(agent);
  const daily = BigInt(agent.daily_cap);
  if (spent + amount > daily) {
    return finish("blocked", `Would be blocked: over today's ${near(daily)} NEAR limit`, `${near(spent)} NEAR already spent today, ${near(daily > spent ? daily - spent : 0n)} NEAR left`, extra);
  }
  const limits = `within ${near(per)} NEAR ${kind} and ${near(daily)} NEAR today (${near(spent)} spent)`;
  const allowed = state.allowlist.includes(receiver);

  if (tier === "untrusted" && !allowed) {
    const who = isSwap ? shown : receiver;
    return finish("wait", `Would wait for the owner's Face ID: ${who} is new and the Inbox Agent can only pay allowed accounts`, `${limits}; the contract holds it until the owner approves`, extra);
  }
  // The server's own checks on a typed payment can only make it stricter: a
  // receiver that isn't allowed and that you've never paid waits for you too.
  if (action.kind === "pay" && !allowed) {
    const facts = await deps.chain.facts(receiver).catch(() => ({ exists: true, isContract: false, createdAtNs: null }));
    if (!facts.exists) return finish("unreadable", `Would not be sent: ${receiver} doesn't exist on NEAR ${cfg.network}`, undefined, extra);
    const checks = judge(facts, allowed, null, false);
    if (checks.verdict === "warn") {
      return finish("wait", `Would wait for the owner's Face ID: ${checks.reasons[0].toLowerCase().replace(/^you've/, "the owner has")}`, `${limits}; the app asks the contract to hold it for approval`, extra);
    }
  }
  if (amount > BigInt(state.available)) {
    return finish("blocked", "Would be blocked: Spend Limits doesn't hold enough NEAR", `it holds ${near(state.available, 2, 2)} NEAR`, extra);
  }
  if (isSwap && action.kind === "swap") {
    return finish("swap", `Would swap ${near(amount)} NEAR to ${action.to}`, limits, extra);
  }
  return finish("pay", `Would pay ${near(amount)} NEAR to ${receiver}`, limits, extra);
}

/** What the contract counts as spent today: nothing when the stored day isn't today. */
export function spentToday(a: AgentView, now = Date.now()): bigint {
  return a.day === Math.floor(now / 86_400_000) ? BigInt(a.spent_today) : 0n;
}

/** "reported by inbox.x: asked for ..." stays; anything long is cut. */
function plainReason(reason: string): string {
  return reason.length > 120 ? `${reason.slice(0, 117)}...` : reason;
}

/** A swap's value in NEAR, where it would go, and live quotes. Only NEAR in can be valued without a price. */
async function swapValue(
  deps: DryRunDeps,
  action: Extract<Action, { kind: "swap" }>,
): Promise<{ value: bigint; venue: string; quotes: [string, string][] } | { error: string }> {
  if (action.from !== "NEAR" || action.usd) {
    return { error: `this dry run checks swaps that spend NEAR (like "swap 0.3 near to usdc"); ${action.from} in needs a live price` };
  }
  let value: bigint;
  try {
    value = BigInt(toYocto(action.amount));
  } catch {
    return { error: `${action.amount} isn't an amount of NEAR` };
  }
  const quotes: [string, string][] = [];
  const route = deps.rhea?.network ? deps.rhea.route(action.to) : undefined;
  const venue = route ? deps.rhea!.network!.exchange : "a NEAR Intents deposit address";
  if (route) {
    try {
      const out = await deps.rhea!.quote(route, value.toString());
      quotes.push(["Rhea", `about ${fromUnits(out, route.decimals)} ${route.symbol} from pool ${route.pool} (where Spend Limits swaps on ${deps.cfg.network})`]);
    } catch (e) {
      quotes.push(["Rhea", `no quote right now (${(e as Error).message.slice(0, 80)})`]);
    }
  }
  if (deps.intents) {
    try {
      const [from, to] = await Promise.all([deps.intents.pick(action.from, "from"), deps.intents.pick(action.to, "to")]);
      if (!to.verified) quotes.push(["NEAR Intents", to.reason]);
      else if (from.verified) {
        const q = await deps.intents.quote(from.token!, to.token!, action.amount);
        const usd = q.amountOutUsd ? ` (~$${Number(q.amountOutUsd).toFixed(2)})` : "";
        quotes.push(["NEAR Intents", `about ${Number(Number(q.amountOutFormatted).toPrecision(4))} ${action.to}${usd}, live mainnet quote`]);
      }
    } catch (e) {
      quotes.push(["NEAR Intents", `no quote right now (${(e as Error).message.slice(0, 80)})`]);
    }
  }
  if (!route && !deps.intents) return { error: `Keybots can't swap NEAR into ${action.to} here` };
  return { value, venue, quotes };
}

/** The lines as two aligned columns. */
export function format(r: DryRun): string {
  const w = Math.max(...r.lines.map(([k]) => k.length)) + 2;
  return [...r.lines.map(([k, v]) => k.padEnd(Math.max(w, 14)) + v), "", FOOTER].join("\n");
}
