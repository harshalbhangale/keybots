// One command, start to finish: read it, pick the agent, check the receiver,
// ask the leash, and write a receipt.
import { randomUUID } from "node:crypto";
import { readWithAi, type AiConfig } from "./ai.js";
import { judge } from "./checks.js";
import type { Config } from "./config.js";
import type { Chain } from "./near.js";
import type { IntentsClient } from "./intents.js";
import type { OrderStore } from "./orders.js";
import { amountOut, fromUnits, minOut, swapMsg, type RheaClient } from "./rhea.js";
import { DOLLAR, parse, resolveReceiver, toYocto, type Action } from "./parse.js";
import type { Receipt, ReceiptStore } from "./receipts.js";

export interface Deps {
  cfg: Config;
  chain: Chain;
  receipts: ReceiptStore;
  readAi?: typeof readWithAi;
  intents?: IntentsClient;
  orders?: OrderStore;
  rhea?: RheaClient;
}

/** The AIs that read what the rules can't, in order: NEAR AI Cloud (private) by default, OpenAI as the fallback. */
export function aiReaders(cfg: Config): AiConfig[] {
  const out: AiConfig[] = [];
  if (cfg.nearAi.apiKey) out.push({ provider: "near-ai-cloud", ...cfg.nearAi });
  if (cfg.openAi?.apiKey && cfg.aiFallback !== "off") out.push({ provider: "openai", ...cfg.openAi });
  return out;
}

/**
 * Read a command: rules first, an AI only for what the rules can't read.
 * NEAR AI Cloud is asked first; if it isn't set up or doesn't answer, OpenAI.
 * Runs nothing.
 */
export async function readCommand(deps: Deps, text: string): Promise<Receipt["interpretation"]> {
  const action = parse(text);
  if (action.kind !== "unknown") return { action, reader: "rules" };
  for (const ai of aiReaders(deps.cfg)) {
    try {
      const read = await (deps.readAi ?? readWithAi)(text, ai);
      return { action: read.action, reader: ai.provider, ai: read.evidence };
    } catch {
      // This one didn't answer: try the next.
    }
  }
  return { action, reader: "rules" };
}

/** What an action is, in words and as the exact command the rules read back the same way. */
export function describe(action: Action): { kind: "pay" | "swap"; title: string; verb: string; command: string } | null {
  const up = (s: string) => s.toUpperCase();
  switch (action.kind) {
    case "pay":
      return {
        kind: "pay",
        title: `Pay ${action.amountNear} NEAR to ${action.receiver}`,
        verb: "pay",
        command: `pay ${action.receiver} ${action.amountNear}${action.memo ? ` for ${action.memo}` : ""}`,
      };
    case "swap":
      if (action.usd) {
        return { kind: "swap", title: `Swap $${action.amount} of ${up(action.from)} to ${up(action.to)}`, verb: "swap", command: `swap $${action.amount} of ${action.from.toLowerCase()} to ${action.to.toLowerCase()}` };
      }
      if (action.from === DOLLAR) {
        return { kind: "swap", title: `Buy $${action.amount} of ${up(action.to)}`, verb: "buy", command: `buy $${action.amount} of ${action.to.toLowerCase()}` };
      }
      return { kind: "swap", title: `Swap ${action.amount} ${up(action.from)} to ${up(action.to)}`, verb: "swap", command: `swap ${action.amount} ${action.from.toLowerCase()} to ${action.to.toLowerCase()}` };
    case "watch":
      return {
        kind: "swap",
        title: `${action.command.charAt(0).toUpperCase()}${action.command.slice(1)} when ${up(action.symbol)} is ${action.direction} $${action.price}`,
        verb: "place",
        command: `${action.command} if it goes ${action.direction} ${action.price}`,
      };
    default:
      return null;
  }
}

export async function runCommand(deps: Deps, text: string, source: "typed" | "pasted"): Promise<Receipt> {
  const { cfg, chain, receipts } = deps;
  const base = { id: randomUUID(), at: new Date().toISOString(), input: { text: text.slice(0, 2000), source } };

  // 1. Read it: rules first, an AI only for what the rules can't read.
  const interpretation = await readCommand(deps, text);
  let action: Action = interpretation.action;

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

  // "$5 of near": how much NEAR that is at NEAR Intents' price right now.
  if (action.usd) {
    const price = from.token!.price;
    if (!price) return done({ outcome: "not-sent", message: `NEAR Intents has no price for ${action.from} right now, so I can't work out $${action.amount} of it.`, swap: { from, to } });
    action = { ...action, amount: String(Number((Number(action.amount) / price).toFixed(4))), usd: false };
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
  // NEAR into a token Rhea has a pool for: swap it for real, from the leash.
  const route = from.token!.assetId.endsWith("wrap.near") ? deps.rhea?.route(action.to) : undefined;
  if (route && deps.rhea?.network) {
    return swapOnRhea(deps, action, agent, route, { from, to, quote, leash }, done);
  }
  // On mainnet, NEAR into anything NEAR Intents lists: fund a 1Click deposit address from the leash.
  if (deps.cfg.network === "mainnet" && from.token!.assetId === "nep141:wrap.near") {
    return swapOnIntents(deps, action, agent, { from, to, quote, leash }, done);
  }
  return done({
    outcome: "quoted",
    message: `Quote: ${action.amount} ${action.from} → ${tidy(quote.amountOutFormatted)} ${action.to}${quote.amountOutUsd ? ` (~$${Number(quote.amountOutUsd).toFixed(2)})` : ""} on NEAR Intents. Nothing sent yet.`,
    agent: { account: agent, tier: "trusted" },
    swap: { from, to, quote, leash },
  });
}

/**
 * Mainnet: a live 1Click quote gives a deposit address; the leash wraps the
 * NEAR and sends the wNEAR there (registering it on wrap.near first). The
 * token goes to the owner (into NEAR Intents for other chains); a failed swap
 * is refunded to the leash. Waits up to a minute for NEAR Intents to finish.
 */
async function swapOnIntents(
  deps: Deps,
  action: Extract<Action, { kind: "swap" }>,
  agent: string,
  swap: NonNullable<Receipt["swap"]>,
  done: (r: Omit<Receipt, "id" | "at" | "input" | "interpretation">) => Receipt,
  wait = { tries: 20, everyMs: 3000 },
): Promise<Receipt> {
  const intents = deps.intents!;
  const label = `${action.amount} NEAR → ${action.to.toUpperCase()}`;
  const who = { account: agent, tier: "trusted" as const };
  let live;
  try {
    live = await intents.liveQuote(swap.from.token!, swap.to.token!, action.amount, { refundTo: deps.cfg.leash, recipient: deps.cfg.owner });
  } catch (e) {
    return done({ outcome: "not-sent", message: `NEAR Intents couldn't quote ${label}: ${(e as Error).message}`, agent: who, swap });
  }
  const { decision, txHash, events } = await deps.chain.swap(agent, {
    venue: live.depositAddress,
    amount: live.amountIn,
    wrap: "wrap.near",
    memo: `swap ${label}`,
  });
  const tx = { hash: txHash, url: deps.chain.txUrl(txHash) };
  if (decision.status !== "paid") {
    return done({ outcome: "blocked", message: `Blocked by the leash (${decision.rule}): ${decision.reason}.`, agent: who, decision, tx, events, swap });
  }
  if (events.some((e) => (e as { event?: string }).event === "swap_failed")) {
    return done({ outcome: "not-sent", message: `The deposit for ${label} didn't go out; the leash keeps the NEAR. Nothing was lost.`, agent: who, decision, tx, events, swap });
  }
  await intents.submitDeposit(txHash, live.depositAddress).catch(() => undefined);
  let progress: Awaited<ReturnType<typeof intents.status>> | undefined;
  for (let i = 0; i < wait.tries; i++) {
    progress = await intents.status(live.depositAddress).catch(() => undefined);
    if (progress?.done) break;
    await new Promise((r) => setTimeout(r, wait.everyMs));
  }
  const ok = progress?.status === "SUCCESS";
  // ok: the deposit went out and nothing failed (done, or still on its way).
  const executed = { venue: "NEAR Intents", exchange: live.depositAddress, amountIn: action.amount, amountOut: progress?.amountOutFormatted ?? live.amountOutFormatted, symbolOut: action.to.toUpperCase(), ok: ok || !progress?.done };
  if (ok) {
    return done({ outcome: "swapped", message: `Swapped ${action.amount} NEAR for ${tidy(executed.amountOut)} ${executed.symbolOut} on NEAR Intents.`, agent: who, decision, tx, events, swap: { ...swap, executed } });
  }
  const why = progress?.status === "REFUNDED" ? "was refunded to the leash" : progress?.done ? "failed; NEAR Intents refunds the leash" : "is still running; it lands in a minute or so";
  return done({ outcome: progress?.done ? "not-sent" : "swapped", message: `The swap of ${label} ${why}.`, agent: who, decision, tx, events, swap: { ...swap, executed } });
}

/** The leash wraps the NEAR and Rhea swaps it in one pool; the token comes back to the leash. */
async function swapOnRhea(
  deps: Deps,
  action: Extract<Action, { kind: "swap" }>,
  agent: string,
  route: NonNullable<ReturnType<RheaClient["route"]>>,
  swap: NonNullable<Receipt["swap"]>,
  done: (r: Omit<Receipt, "id" | "at" | "input" | "interpretation">) => Receipt,
): Promise<Receipt> {
  const net = deps.rhea!.network!;
  const label = `${action.amount} NEAR → ${route.symbol}`;
  let amountIn: string;
  try {
    amountIn = toYocto(action.amount);
  } catch {
    return done({ outcome: "not-sent", message: `${action.amount} isn't an amount I can swap.`, swap });
  }
  let expected: string;
  try {
    expected = await deps.rhea!.quote(route, amountIn);
  } catch (e) {
    return done({ outcome: "not-sent", message: `Rhea couldn't price ${label}: ${(e as Error).message}`, swap });
  }
  const { decision, txHash, events, logs } = await deps.chain.swap(agent, {
    venue: net.exchange,
    amount: amountIn,
    wrap: net.wrap,
    msg: swapMsg(net, route, amountIn, minOut(expected)),
    memo: `swap ${label}`,
  });
  const tx = { hash: txHash, url: deps.chain.txUrl(txHash) };
  const who = { account: agent, tier: "trusted" as const };
  if (decision.status !== "paid") {
    return done({ outcome: "blocked", message: `Blocked by the leash (${decision.rule}): ${decision.reason}.`, agent: who, decision, tx, events, swap });
  }
  const failed = events.some((e) => (e as { event?: string }).event === "swap_failed");
  const out = amountOut(logs, route.token);
  const executed = { venue: "Rhea", exchange: net.exchange, amountIn: action.amount, amountOut: out ? fromUnits(out, route.decimals) : undefined, symbolOut: route.symbol, ok: !failed && !!out };
  if (!executed.ok) {
    return done({
      outcome: "not-sent",
      message: `Rhea didn't fill ${label}; the leash keeps the NEAR as wNEAR. Nothing was lost.`,
      agent: who,
      decision,
      tx,
      events,
      swap: { ...swap, executed },
    });
  }
  return done({
    outcome: "swapped",
    message: `Swapped ${action.amount} NEAR for ${executed.amountOut} ${route.symbol} on Rhea. It's in the leash.`,
    agent: who,
    decision,
    tx,
    events,
    swap: { ...swap, executed },
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
