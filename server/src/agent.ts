// One command, start to finish: read it, pick the agent, check the receiver,
// ask the leash, and write a receipt.
import { randomUUID } from "node:crypto";
import { readWithNearAi } from "./ai.js";
import { judge } from "./checks.js";
import type { Config } from "./config.js";
import type { Chain } from "./near.js";
import { parse, resolveReceiver, toYocto, type Action } from "./parse.js";
import type { Receipt, ReceiptStore } from "./receipts.js";

export interface Deps {
  cfg: Config;
  chain: Chain;
  receipts: ReceiptStore;
  readAi?: typeof readWithNearAi;
}

export async function runCommand(deps: Deps, text: string, source: "typed" | "pasted"): Promise<Receipt> {
  const { cfg, chain, receipts } = deps;
  const base = { id: randomUUID(), at: new Date().toISOString(), input: { text: text.slice(0, 2000), source } };

  // 1. Read it: rules first, NEAR AI Cloud only for what the rules can't read.
  let action: Action = parse(text);
  let interpretation: Receipt["interpretation"] = { action, reader: "rules" };
  if (action.kind === "unknown" && cfg.nearAi.apiKey) {
    try {
      const ai = await (deps.readAi ?? readWithNearAi)(text, cfg.nearAi);
      action = ai.action;
      interpretation = { action, reader: "near-ai-cloud", ai: ai.evidence };
    } catch (e) {
      interpretation = { action, reader: "rules" };
    }
  }

  const done = (r: Omit<Receipt, "id" | "at" | "input" | "interpretation">): Receipt => {
    const receipt = { ...base, interpretation, ...r } as Receipt;
    receipts.add(receipt);
    return receipt;
  };

  if (action.kind === "unknown") return done({ outcome: "not-sent", message: action.reason });
  if (action.kind === "swap") {
    return done({ outcome: "not-sent", message: `Swap ${action.amount} ${action.from} → ${action.to}: swaps through NEAR Intents aren't built yet.` });
  }

  // 2. Who is it for?
  const to = resolveReceiver(action.receiver, cfg.contacts, cfg.network);
  if ("error" in to) return done({ outcome: "not-sent", message: to.error });
  const receiver = { asked: action.receiver, account: to.account, via: to.via };

  let amount: string;
  try {
    amount = toYocto(action.amountNear);
    if (BigInt(amount) <= 0n) throw new Error();
  } catch {
    return done({ outcome: "not-sent", message: `${action.amountNear} isn't an amount I can send.`, receiver });
  }

  // 3. Which agent: what you typed is trusted; what someone else wrote is not.
  const agent = source === "typed" ? { account: cfg.agents.trusted, tier: "trusted" as const } : { account: cfg.agents.untrusted, tier: "untrusted" as const };

  // 4. Off-chain checks on the receiver. They can only make it stricter.
  const [facts, allowlisted, blocked] = await Promise.all([
    chain.facts(receiver.account),
    chain.isAllowed(receiver.account),
    chain.blockedReason(receiver.account),
  ]);
  const checks = judge(facts, allowlisted, blocked, receipts.paidBefore(receiver.account));
  if (!facts.exists) {
    return done({ outcome: "not-sent", message: `${receiver.account} doesn't exist on NEAR ${cfg.network}. Nothing was sent.`, agent, receiver, checks });
  }

  // 5. Ask the leash. It decides; we only report.
  const { decision, txHash, events } = await chain.pay(agent.account, {
    receiver: receiver.account,
    amount,
    ...(action.memo ? { memo: action.memo } : {}),
    ask_owner: checks.verdict === "warn",
  });
  const tx = { hash: txHash, url: chain.txUrl(txHash) };
  const amountText = `${action.amountNear} NEAR`;

  if (decision.status === "paid") {
    return done({ outcome: "paid", message: `Paid ${amountText} to ${receiver.account}`, agent, receiver, checks, decision, tx, events });
  }
  if (decision.status === "pending") {
    const why = decision.rule === "R7" ? checks.reasons.join(". ") : decision.reason;
    return done({ outcome: "approval", message: `Needs your approval: ${amountText} to ${receiver.account}. ${why}.`, agent, receiver, checks, decision, tx, events });
  }
  return done({
    outcome: "blocked",
    message: `Blocked by the leash (${decision.rule}): ${decision.reason}.`,
    agent,
    receiver,
    checks,
    decision,
    tx,
    events,
  });
}
