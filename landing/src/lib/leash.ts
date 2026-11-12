// A browser copy of the leash's decision order (RULES.md, contracts/leash/src/lib.rs).
// It runs locally for the landing page's demo; the real decisions happen on NEAR testnet.

import { useSyncExternalStore } from "react";

export type Source = "typed" | "pasted";
export type AgentId = "pay" | "inbox";
export type Outcome = "paid" | "pending" | "blocked" | "none";
export type RuleId = "R1" | "R2" | "R3" | "R4" | "R5" | "R6" | "R7" | "R0" | "OK";

export type Agent = {
  id: AgentId;
  account: string;
  tier: "trusted" | "untrusted";
  perPaymentCap: number;
  dailyCap: number;
  spentToday: number;
};

export type Intent = {
  receiver: string; // resolved account
  name: string; // what was typed
  amount: number;
  memo?: string;
};

export type Decision = {
  id: number;
  text: string;
  source: Source;
  agent: AgentId;
  intent: Intent | null;
  outcome: Outcome;
  rule: RuleId;
  reason: string;
  askOwner: boolean;
  trace: { rule: RuleId; label: string; result: "pass" | "fire" }[];
  reported?: string;
  at: number;
};

export type LeashState = {
  paused: boolean;
  balance: number;
  allowlist: string[];
  blocklist: string[];
  paidBefore: string[];
  agents: Record<AgentId, Agent>;
  pending: Decision[];
  log: Decision[];
};

export const CONTACTS: Record<string, { account: string; note: string }> = {
  harshal: { account: "harshal.near", note: "friend, allowlisted, paid before" },
  "harshal.near": { account: "harshal.near", note: "friend, allowlisted, paid before" },
  designer: { account: "designer.near", note: "new account, never paid" },
  "designer.near": { account: "designer.near", note: "new account, never paid" },
  drain: { account: "drain.near", note: "the scammer" },
  "drain.near": { account: "drain.near", note: "the scammer" },
  mom: { account: "mom.near", note: "allowlisted" },
  "mom.near": { account: "mom.near", note: "allowlisted" },
};

const initial = (): LeashState => ({
  paused: false,
  balance: 3,
  allowlist: ["harshal.near", "mom.near"],
  blocklist: [],
  paidBefore: ["harshal.near", "mom.near"],
  agents: {
    pay: { id: "pay", account: "pay.airkey-harshal.testnet", tier: "trusted", perPaymentCap: 0.5, dailyCap: 1, spentToday: 0 },
    inbox: { id: "inbox", account: "inbox.airkey-harshal.testnet", tier: "untrusted", perPaymentCap: 0.5, dailyCap: 1, spentToday: 0 },
  },
  pending: [],
  log: [],
});

/* ---------- parsing (the server's rules-first reader, simplified) ---------- */

const NUM = "(\\d+(?:\\.\\d+)?)";
const WHO = "([a-z0-9_\\-.]+)";

export function parse(text: string): { kind: "pay"; intent: Intent } | { kind: "swap" } | { kind: "none" } {
  const t = text.toLowerCase().replace(/[,!]/g, " ").replace(/\s+/g, " ").trim();
  if (/\bswap\b/.test(t)) return { kind: "swap" };

  // "pay 5 near to drain.near", "send 5 NEAR to drain.near"
  let m = t.match(new RegExp(`\\b(?:pay|send|transfer)\\s+${NUM}\\s*(?:near|Ⓝ)?\\s+to\\s+${WHO}(?:\\s+for\\s+(.+))?`));
  if (m) return { kind: "pay", intent: resolve(m[2], parseFloat(m[1]), m[3]) };

  // "pay harshal 0.5 for dinner", "pay harshal.near 0.2 near for dinner"
  m = t.match(new RegExp(`\\b(?:pay|send)\\s+${WHO}\\s+${NUM}\\s*(?:near|Ⓝ)?(?:\\s+for\\s+(.+))?`));
  if (m) return { kind: "pay", intent: resolve(m[1], parseFloat(m[2]), m[3]) };

  return { kind: "none" };
}

function resolve(name: string, amount: number, memo?: string): Intent {
  const clean = name.replace(/\.$/, "");
  const c = CONTACTS[clean];
  const receiver = c ? c.account : clean.includes(".") ? clean : `${clean}.near`;
  return { receiver, name: clean, amount, memo: memo?.replace(/[.]+$/, "").trim() || undefined };
}

export function describe(text: string, source: Source): string {
  const p = parse(text);
  if (p.kind === "swap") return "A swap: the server quotes these through NEAR Intents. Try a payment here.";
  if (p.kind === "none") return text.trim() ? "No payment found in that." : "";
  const who = source === "typed" ? "Pay Agent (trusted)" : "Inbox Agent (untrusted)";
  return `Pay ${fmt(p.intent.amount)} NEAR to ${p.intent.receiver}${p.intent.memo ? ` for ${p.intent.memo}` : ""} · goes to the ${who}`;
}

export const fmt = (n: number) => (Math.round(n * 1000) / 1000).toString();

/* ---------- the leash ---------- */

export const RULES: { id: RuleId; label: string; result: Outcome | "panic" }[] = [
  { id: "R1", label: "Kill switch is on", result: "blocked" },
  { id: "R2", label: "Caller is a registered agent", result: "panic" },
  { id: "R3", label: "Receiver is on the blocklist", result: "blocked" },
  { id: "R4", label: "Over the per-payment cap", result: "blocked" },
  { id: "R5", label: "Over the daily cap", result: "blocked" },
  { id: "R6", label: "Untrusted agent, receiver not allowlisted", result: "pending" },
  { id: "R7", label: "Agent asked the owner (check warned)", result: "pending" },
  { id: "R0", label: "Leash holds enough NEAR", result: "blocked" },
];

function decide(s: LeashState, agent: Agent, intent: Intent, askOwner: boolean) {
  const trace: Decision["trace"] = [];
  const pass = (rule: RuleId) => trace.push({ rule, label: RULES.find((r) => r.id === rule)!.label, result: "pass" });
  const fire = (rule: RuleId, outcome: Outcome, reason: string) => {
    trace.push({ rule, label: RULES.find((r) => r.id === rule)!.label, result: "fire" });
    return { outcome, rule, reason, trace };
  };

  if (s.paused) return fire("R1", "blocked", "The kill switch is on.");
  pass("R1");
  pass("R2");
  if (s.blocklist.includes(intent.receiver)) return fire("R3", "blocked", `${intent.receiver} is on the blocklist.`);
  pass("R3");
  if (intent.amount > agent.perPaymentCap)
    return fire("R4", "blocked", `Over the per-payment cap of ${fmt(agent.perPaymentCap)} NEAR.`);
  pass("R4");
  if (agent.spentToday + intent.amount > agent.dailyCap)
    return fire("R5", "blocked", `Over the daily cap: ${fmt(agent.spentToday)} of ${fmt(agent.dailyCap)} NEAR spent today.`);
  pass("R5");
  if (agent.tier === "untrusted" && !s.allowlist.includes(intent.receiver))
    return fire("R6", "pending", "Someone else's words, to an account you haven't allowed. Waiting for you.");
  pass("R6");
  if (askOwner) return fire("R7", "pending", `${intent.receiver} is new and you've never paid it, so the agent asked you.`);
  pass("R7");
  if (s.balance < intent.amount) return fire("R0", "blocked", "The leash doesn't hold enough NEAR.");
  pass("R0");
  trace.push({ rule: "OK", label: "Paid: the leash sends the NEAR", result: "fire" });
  return { outcome: "paid" as Outcome, rule: "OK" as RuleId, reason: `Sent ${fmt(intent.amount)} NEAR to ${intent.receiver}.`, trace };
}

/* ---------- store ---------- */

let state = initial();
let nextId = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());
const set = (fn: (s: LeashState) => LeashState) => {
  state = fn(state);
  emit();
};

export const leash = {
  get: () => state,
  subscribe(l: () => void) {
    listeners.add(l);
    return () => listeners.delete(l);
  },

  run(text: string, source: Source): Decision {
    const agentId: AgentId = source === "typed" ? "pay" : "inbox";
    const p = parse(text);
    const base = { id: nextId++, text, source, agent: agentId, at: Date.now(), askOwner: false };
    if (p.kind !== "pay") {
      const d: Decision = {
        ...base,
        intent: null,
        outcome: "none",
        rule: "OK",
        reason: p.kind === "swap" ? "Swaps are quoted by the server through NEAR Intents; this demo runs payments." : "I couldn't find a payment in that.",
        trace: [],
      };
      set((s) => ({ ...s, log: [d, ...s.log].slice(0, 30) }));
      return d;
    }
    const agent = state.agents[agentId];
    // The server's receiver check: a new account you've never paid makes the agent ask (R7).
    const askOwner = !state.paidBefore.includes(p.intent.receiver);
    const r = decide(state, agent, p.intent, askOwner);
    const d: Decision = { ...base, intent: p.intent, askOwner, ...r };

    set((s) => {
      let next = { ...s, log: [d, ...s.log].slice(0, 30) };
      if (d.outcome === "paid") {
        next.balance = s.balance - p.intent.amount;
        next.agents = { ...s.agents, [agentId]: { ...agent, spentToday: agent.spentToday + p.intent.amount } };
        if (!s.paidBefore.includes(p.intent.receiver)) next.paidBefore = [...s.paidBefore, p.intent.receiver];
      }
      if (d.outcome === "pending") next.pending = [...s.pending, d];
      // An injected payment that was blocked gets reported: the receiver goes on the blocklist at once.
      if (d.outcome === "blocked" && source === "pasted" && d.rule === "R4" && !s.blocklist.includes(p.intent.receiver)) {
        d.reported = p.intent.receiver;
        next.blocklist = [...s.blocklist, p.intent.receiver];
      }
      return next;
    });
    return d;
  },

  approve(id: number) {
    const d = state.pending.find((x) => x.id === id);
    if (!d || !d.intent) return;
    const intent = d.intent;
    set((s) => {
      const pending = s.pending.filter((x) => x.id !== id);
      // Approve re-checks R1 and R3; the amount counts toward the agent's daily spend.
      if (s.paused || s.blocklist.includes(intent.receiver)) return { ...s, pending };
      const agent = s.agents[d.agent];
      const ok: Decision = {
        ...d,
        id: nextId++,
        outcome: "paid",
        rule: "OK",
        reason: `You approved it. Sent ${fmt(intent.amount)} NEAR to ${intent.receiver}.`,
        trace: [{ rule: "OK", label: "Owner approved", result: "fire" }],
        at: Date.now(),
      };
      return {
        ...s,
        pending,
        balance: s.balance - intent.amount,
        paidBefore: s.paidBefore.includes(intent.receiver) ? s.paidBefore : [...s.paidBefore, intent.receiver],
        agents: { ...s.agents, [d.agent]: { ...agent, spentToday: agent.spentToday + intent.amount } },
        log: [ok, ...s.log].slice(0, 30),
      };
    });
  },

  reject(id: number) {
    set((s) => ({ ...s, pending: s.pending.filter((x) => x.id !== id) }));
  },

  setPaused(paused: boolean) {
    set((s) => ({ ...s, paused }));
  },

  reset() {
    state = initial();
    emit();
  },
};

export function useLeash() {
  return useSyncExternalStore(leash.subscribe, leash.get, leash.get);
}
