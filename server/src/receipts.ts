// AIRKEY Receipts: one line per command, stored as JSONL. The on-chain events
// are the source of truth; a receipt adds what happened before the chain: the
// words, how they were read, which agent, and the checks.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { AiEvidence } from "./ai.js";
import type { CheckResult } from "./checks.js";
import type { Action } from "./parse.js";
import type { Decision } from "./near.js";

export interface Receipt {
  id: string;
  at: string;
  input: { text: string; source: "typed" | "pasted" };
  interpretation: { action: Action; reader: "rules" | "near-ai-cloud"; ai?: AiEvidence };
  agent?: { account: string; tier: "trusted" | "untrusted" };
  receiver?: { asked: string; account: string; via: "contacts" | "account" };
  checks?: CheckResult;
  /** The leash's answer, straight from the chain. */
  decision?: Decision;
  /** Shown to the person: allow (mint), warn (amber), block (red), or info. */
  outcome: "paid" | "approval" | "blocked" | "not-sent";
  message: string;
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
