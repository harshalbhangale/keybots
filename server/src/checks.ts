// Off-chain checks on a receiver before an agent asks the leash to pay.
// They can only make things stricter: "warn" makes the agent ask the owner
// (the leash's R7). They can't loosen anything the leash enforces.
import type { AccountFacts } from "./near.js";

export type Verdict = "allow" | "warn" | "block";

export interface CheckResult {
  verdict: Verdict;
  reasons: string[];
  facts: AccountFacts & { allowlisted: boolean; blocked: string | null; paidBefore: boolean; ageDays: number | null };
}

export const NEW_ACCOUNT_DAYS = 7;

export function judge(
  facts: AccountFacts,
  allowlisted: boolean,
  blocked: string | null,
  paidBefore: boolean,
  nowMs = Date.now(),
): CheckResult {
  const ageDays = facts.createdAtNs ? (nowMs - Number(BigInt(facts.createdAtNs) / 1_000_000n)) / 86_400_000 : null;
  const all = { ...facts, allowlisted, blocked, paidBefore, ageDays: ageDays === null ? null : Math.floor(ageDays) };
  const reasons: string[] = [];

  if (blocked) return { verdict: "block", reasons: [`On your blocklist: ${blocked}`], facts: all };
  if (!facts.exists) return { verdict: "block", reasons: ["This account doesn't exist"], facts: all };
  if (allowlisted) return { verdict: "allow", reasons: ["On your allowlist"], facts: all };

  const isNew = ageDays !== null && ageDays < NEW_ACCOUNT_DAYS;
  if (paidBefore && !isNew && !facts.isContract) return { verdict: "allow", reasons: ["You've paid this account before"], facts: all };

  if (isNew) reasons.push(`New account: created ${Math.max(0, Math.floor(ageDays!))} day(s) ago`);
  if (facts.isContract) reasons.push("This is a contract, not a person");
  if (!paidBefore) reasons.push("You've never paid this account");
  if (ageDays === null) reasons.push("Couldn't check the account's age");
  return { verdict: "warn", reasons, facts: all };
}
