// One command, start to finish: read it, pick the agent, check the receiver,
// ask the leash, and write a receipt.
import { randomUUID } from "node:crypto";
import { readWithNearAi } from "./ai.js";
import { judge } from "./checks.js";
import type { Config } from "./config.js";
import type { Chain } from "./near.js";
import type { IntentsClient } from "./intents.js";
import type { OrderStore } from "./orders.js";
import { parse, resolveReceiver, toYocto, type Action } from "./parse.js";
import type { Receipt, ReceiptStore } from "./receipts.js";

export interface Deps {
  cfg: Config;
  chain: Chain;
  receipts: ReceiptStore;
  readAi?: typeof readWithNearAi;
  intents?: IntentsClient;
  orders?: OrderStore;
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
  if (action.kind === "swap") return swap(deps, action, source, done);
  if (action.kind === "watch") return watch(deps, action, text, source, done);

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

const nearToYocto = (n: number) => BigInt(Math.round(n * 1e6)) * 10n ** 18n;
const yoctoToNear = (y: bigint) => (Number(y / 10n ** 18n) / 1e6).toString();
/** A number for a sentence: "2.933176326443593989515722" -> "2.933", "0.024441517" -> "0.02444". */
export const tidy = (n: string | number) => {
  const v = Number(n);
  if (!Number.isFinite(v)) return String(n);
  return String(Number(v.toPrecision(4)));
};

/** Swaps: check both tokens against NEAR Intents, get a dry-run quote, and hold its value to the leash's caps. */
async function swap(
  deps: Deps,
  action: Extract<Action, { kind: "swap" }>,
  source: "typed" | "pasted",
  done: (r: Omit<Receipt, "id" | "at" | "input" | "interpretation">) => Receipt,
): Promise<Receipt> {
  const label = `${action.amount} ${action.from} → ${action.to}`;
  if (source === "pasted") {
    return done({ outcome: "blocked", message: `Swaps only run from what you type. The Inbox Agent can't trade (${label}).` });
  }
  if (!deps.intents) return done({ outcome: "not-sent", message: `Swaps aren't set up on this server (${label}).` });

  const [from, to] = await Promise.all([deps.intents.pick(action.from, "from"), deps.intents.pick(action.to, "to")]);
  if (!from.verified || !to.verified) {
    const bad = !from.verified ? from : to;
    return done({ outcome: "blocked", message: `Token check failed: ${bad.reason}.`, swap: { from, to } });
  }

  let quote;
  try {
    quote = await deps.intents.quote(from.token!, to.token!, action.amount);
  } catch (e) {
    return done({ outcome: "not-sent", message: `NEAR Intents couldn't quote ${label}: ${(e as Error).message}`, swap: { from, to } });
  }

  // What it's worth in NEAR, held to the Trading Agent's caps as the leash has them on chain.
  // A deployment without a Trading Agent falls back to the Payment Agent's caps.
  const nearPrice = (await deps.intents.tokens()).find((t) => t.assetId === "nep141:wrap.near")?.price;
  const usd = Number(quote.amountInUsd ?? 0);
  const state = await deps.chain.state();
  const agent = state.agents.some((x) => x.account === deps.cfg.agents.trade) ? deps.cfg.agents.trade : deps.cfg.agents.trusted;
  let leash: NonNullable<Receipt["swap"]>["leash"];
  if (nearPrice && usd > 0) {
    const a = state.agents.find((x) => x.account === agent)?.agent;
    if (a) {
      const value = nearToYocto(usd / nearPrice);
      const left = BigInt(a.daily_cap) - BigInt(a.spent_today);
      const within = !state.paused && value <= BigInt(a.per_payment_cap) && value <= left;
      leash = { agent, valueNear: yoctoToNear(value), perPaymentCap: a.per_payment_cap, leftToday: (left > 0n ? left : 0n).toString(), within };
      if (!within) {
        const why = state.paused
          ? "the kill switch is on"
          : value > BigInt(a.per_payment_cap)
            ? `it's worth about ${tidy(yoctoToNear(value))} NEAR, over the ${yoctoToNear(BigInt(a.per_payment_cap))} NEAR per-trade cap`
            : `only ${tidy(yoctoToNear(left > 0n ? left : 0n))} NEAR is left today`;
        return done({
          outcome: "blocked",
          message: `The leash would block this: ${why}.`,
          agent: { account: agent, tier: "trusted" },
          swap: { from, to, quote, leash },
        });
      }
    }
  }
  return done({
    outcome: "quoted",
    message: `Quote: ${action.amount} ${action.from} → ${tidy(quote.amountOutFormatted)} ${action.to}${quote.amountOutUsd ? ` (~$${Number(quote.amountOutUsd).toFixed(2)})` : ""} on NEAR Intents. Nothing sent yet.`,
    agent: { account: agent, tier: "trusted" },
    swap: { from, to, quote, leash },
  });
}

/** A price-triggered order: check the trade and the token now, then leave it with the watcher. */
async function watch(
  deps: Deps,
  action: Extract<Action, { kind: "watch" }>,
  text: string,
  source: "typed" | "pasted",
  done: (r: Omit<Receipt, "id" | "at" | "input" | "interpretation">) => Receipt,
): Promise<Receipt> {
  const what = `${action.command} when ${action.symbol} is ${action.direction} $${action.price}`;
  if (source === "pasted") {
    return done({ outcome: "blocked", message: `Orders only come from what you type. The Inbox Agent can't set one (${what}).` });
  }
  if (!deps.intents || !deps.orders) return done({ outcome: "not-sent", message: `Orders aren't set up on this server (${what}).` });

  // Both tokens must be real before anything is left waiting.
  const [from, to] = await Promise.all([deps.intents.pick(action.trade.from, "from"), deps.intents.pick(action.trade.to, "to")]);
  if (!from.verified || !to.verified) {
    const bad = !from.verified ? from : to;
    return done({ outcome: "blocked", message: `Token check failed: ${bad.reason}.`, swap: { from, to } });
  }
  const now = await deps.intents.price(action.symbol);
  if (now === undefined) return done({ outcome: "not-sent", message: `NEAR Intents has no price for ${action.symbol} right now.`, swap: { from, to } });

  const target = Number(action.price);
  const order = deps.orders.add({ text: text.slice(0, 500), command: action.command, symbol: action.symbol, direction: action.direction, price: target, priceThen: now });
  const agent = (await deps.chain.state()).agents.some((x) => x.account === deps.cfg.agents.trade) ? deps.cfg.agents.trade : deps.cfg.agents.trusted;
  return done({
    outcome: "watching",
    message: `Watching ${action.symbol} (now $${tidy(now)}). When it's ${action.direction} $${tidy(target)}: ${action.command}.`,
    agent: { account: agent, tier: "trusted" },
    swap: { from, to },
    order: { id: order.id, symbol: order.symbol, direction: order.direction, price: order.price, priceThen: order.priceThen, command: order.command },
  });
}
