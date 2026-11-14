// AIRKEY Receipts: one line per command, stored as JSONL. The on-chain events
// are the source of truth; a receipt adds what happened before the chain: the
// words, how they were read, which agent, and the checks.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { AiEvidence } from "./ai.js";
import type { CheckResult } from "./checks.js";
import type { Action } from "./parse.js";
import type { Decision } from "./near.js";
import type { SwapQuote, TokenCheck } from "./intents.js";

/**
 * "follow": the server built the command from a followed KOL's call, under the owner's rules for them.
 * "reviewed-call": a KOL's call the owner reviewed (exact amounts, venue, limits) and confirmed (trade.ts).
 */
export type Source = "typed" | "pasted" | "follow" | "reviewed-call";

export interface Receipt {
  id: string;
  at: string;
  /**
   * Where the words came from: typed by the owner, pasted from someone else,
   * or a call from a KOL the owner follows (with who posted it and where).
   */
  input: { text: string; source: Source; handle?: string; postUrl?: string };
  interpretation: { action: Action; reader: "rules" | "near-ai-cloud" | "openai"; ai?: AiEvidence };
  agent?: { account: string; tier: "trusted" | "untrusted" };
  receiver?: { asked: string; account: string; via: "contacts" | "account" };
  checks?: CheckResult;
  /** The leash's answer, straight from the chain. */
  decision?: Decision;
  /** A swap: the token checks, the NEAR Intents quote, and the leash caps it was held to. */
  swap?: {
    from: TokenCheck;
    to: TokenCheck;
    quote?: SwapQuote;
    leash?: { agent: string; valueNear: string; perPaymentCap: string; leftToday: string; within: boolean };
    /** A swap that really ran: where, what went in and what came back to the leash. */
    executed?: { venue: string; exchange: string; amountIn: string; /** What was sold, when it wasn't NEAR. */ symbolIn?: string; amountOut?: string; symbolOut: string; ok: boolean };
  };
  /** Shown to the person: allow (mint), warn (amber), block (red), quote, or info. */
  outcome: "paid" | "swapped" | "approval" | "blocked" | "quoted" | "watching" | "not-sent";
  /** A price-triggered order this command created. */
  order?: { id: string; symbol: string; direction: "below" | "above"; price: number; priceThen: number; command: string };
  message: string;
  /** The same thing in plain words, with no rule codes: what the keyboard and the app show first. */
  summary?: string;
  tx?: { hash: string; url: string };
  events?: unknown[];
}

export interface ReceiptStore {
  add(r: Receipt): void;
  list(limit?: number): Receipt[];
  paidBefore(account: string): boolean;
}

export function fileStore(dir: string): ReceiptStore {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, "receipts.jsonl");
  const read = (): Receipt[] =>
    existsSync(file)
      ? readFileSync(file, "utf8")
          .split("\n")
          .filter(Boolean)
          .map((l) => JSON.parse(l) as Receipt)
      : [];
  return {
    add: (r) => appendFileSync(file, JSON.stringify(r) + "\n"),
    list: (limit = 50) => read().reverse().slice(0, limit),
    paidBefore: (account) => read().some((r) => r.outcome === "paid" && r.receiver?.account === account),
  };
}

export function memoryStore(): ReceiptStore {
  const all: Receipt[] = [];
  return {
    add: (r) => void all.push(r),
    list: (limit = 50) => [...all].reverse().slice(0, limit),
    paidBefore: (account) => all.some((r) => r.outcome === "paid" && r.receiver?.account === account),
  };
}
