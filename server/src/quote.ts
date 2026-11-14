// The trade panel's numbers: what a swap pays, what it gets, by which route,
// what it costs and whether the leash would let it through. Every figure is
// read from somewhere real: Rhea's pool (get_return), NEAR Intents' token
// list and dry quote, and the leash's own state on chain. Nothing is sent.
//
// A quote also carries `command`, the exact text a hold sends to /v1/command,
// so what runs is what was shown.
import type { Config } from "./config.js";
import { pickToken, toUnits, type IntentsClient, type IntentsToken } from "./intents.js";
import type { LeashState } from "./near.js";
import { minOut, RHEA, sellRoute, type RheaNetwork, type RheaRoute } from "./rhea.js";

/** What Rhea's pool `pool` returns for `amountIn` units of `tokenIn`, in `tokenOut` units. */
export type PoolReturn = (pool: number, tokenIn: string, tokenOut: string, amountIn: string) => Promise<string>;

export interface QuoteDeps {
  cfg: Pick<Config, "network" | "leash" | "agents" | "mainnetUsdCap">;
  /** `tokenCap`: the owner's rule for selling a token; null (or absent) means the leash can't sell it. */
  chain: { state(): Promise<LeashState>; tokenCap?(token: string): Promise<{ max_per_trade: string } | null> };
  intents?: Pick<IntentsClient, "tokens" | "quote">;
  /** The pools here, when the network has any (testnet). */
  rhea?: { network?: RheaNetwork; holdings(account: string): Promise<{ symbol: string; token: string; amount: string }[]> };
  poolReturn?: PoolReturn;
  now?: () => number;
}

export interface QuoteToken {
  symbol: string;
  assetId: string | null;
  /** Dollars, from NEAR Intents' list. */
  price: number | null;
  verified: boolean;
}

export type OrderKind = "limit" | "stop" | "take";

export interface TradeQuote {
  from: QuoteToken;
  to: QuoteToken;
  amountIn: string;
  amountOut: string;
  /** "1 NEAR = 2.10 USDC" */
  rate: string;
  /** The least the swap may return: 1% under the quote. */
  minReceived: string;
  slippagePct: number;
  route: { venue: "Rhea"; pool: number; pools: number[] } | { venue: "NEAR Intents"; seconds: number | null };
  /** True only if a hold would really swap on this network. */
  executable: boolean;
  /** Why not, in one plain line. */
  reason: string | null;
  /** Gas for the leash's swap call, paid by the Trading Agent. Measured, not estimated per trade. */
  networkFee: { amount: string; symbol: "NEAR"; usd: string | null };
  /** Percent lost to the size of the trade: this size against a tiny one in the same pool. */
  priceImpact: number | null;
  /** Percent above (+) or below (-) NEAR Intents' dollar prices. */
  vsMarket: number | null;
  valueUsd: string | null;
  caps: { agent: string; perTrade: string; leftToday: string; paused: boolean; valueNear: string | null; within: boolean } | null;
  /** What the leash holds of the token being paid. */
  balance: { symbol: string; amount: string; enough: boolean } | null;
  /** The exact text a hold sends to /v1/command. */
  command: string;
  /** One plain line when the hold is off (not executable, over a cap, not enough). */
  problem: string | null;
  /** Everything checks out: the hold may run. */
  ready: boolean;
  /** Set when the panel asked for a price-triggered order. */
  order?: {
    kind: OrderKind;
    /** The token whose price is watched. */
    symbol: string;
    direction: "below" | "above";
    trigger: string;
    /** Its price now, on NEAR Intents. */
    now: number | null;
    /** "Sells 1 NEAR for USDC when NEAR is below $2." */
    line: string;
  };
}

export interface PickerToken {
  symbol: string;
  chain: string;
  price: number | null;
  /** What the leash holds, when it holds any. */
  balance: string | null;
  /** A hold can really swap it on this network. */
  tradable: boolean;
}

export class QuoteError extends Error {
  constructor(
    message: string,
    public status = 400,
  ) {
    super(message);
  }
}

/**
 * Gas the leash's swap burns, in NEAR. Measured from two testnet swaps
 * (32m4Cq1WckDfvHPxDCKSioDReWHgBr42zm1rSThSRovC and
 * HvJjVCxfd9Q99DJ7bjCK3sH4YduHkuH1qACBwoJkkeWR): 19 receipts, 26.06 TGas,
 * 0.002405 NEAR burnt each.
 */
export const SWAP_FEE_NEAR = "0.0024";
/** How long a Rhea-routed quote waits on the leash's state before it goes without caps. */
const STATE_WAIT_MS = 1100;
/** How long a NEAR Intents-only quote may take. */
const INTENTS_WAIT_MS = 4000;
const STATE_FRESH_MS = 4000;
const STABLE = new Set(["USDC", "USDT", "DAI"]);
const NEAR_DECIMALS = 24;

const isNear = (s: string) => s === "NEAR" || s === "WNEAR";
/** "2.933176326" -> "2.933"; small numbers keep four significant digits. */
export const tidy = (n: number) => (Number.isFinite(n) ? String(Number(n.toPrecision(n >= 1000 ? 7 : 4))) : "0");
const usd = (n: number) => (n >= 100 ? n.toFixed(0) : n >= 0.01 ? n.toFixed(2) : String(Number(n.toPrecision(2))));
const yoctoToNear = (y: bigint) => Number(y / 10n ** 18n) / 1e6;
/** Units to a number, keeping nine digits after the point. */
const unitsToNumber = (units: string, decimals: number) => Number((BigInt(units) * 10n ** 9n) / 10n ** BigInt(decimals)) / 1e9;
const timeout = <T>(p: Promise<T>, ms: number): Promise<T | null> =>
  Promise.race([p.catch(() => null), new Promise<null>((r) => setTimeout(() => r(null), ms))]);

/** Rhea's get_return over NEAR RPC. */
export function rheaPoolReturn(rpc: string, exchange: string, fetchImpl: typeof fetch = fetch): PoolReturn {
  return async (pool, tokenIn, tokenOut, amountIn) => {
    const args = { pool_id: pool, token_in: tokenIn, amount_in: amountIn, token_out: tokenOut };
    const r = await fetchImpl(rpc, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: "airkey",
        method: "query",
        params: { request_type: "call_function", finality: "final", account_id: exchange, method_name: "get_return", args_base64: Buffer.from(JSON.stringify(args)).toString("base64") },
      }),
      signal: AbortSignal.timeout(8000),
    });
    const j = (await r.json()) as { result?: { result?: number[]; error?: string }; error?: { message?: string } };
    if (!j.result?.result) throw new Error(j.result?.error ?? j.error?.message ?? "NEAR RPC didn't answer");
    return JSON.parse(Buffer.from(j.result.result).toString()) as string;
  };
}

interface Hop {
  pool: number;
  tokenIn: string;
  tokenOut: string;
}

/**
 * The pool a pair goes through on Rhea here, as the leash would trade it:
 * NEAR into a token, a token back to NEAR, or two tokens that share a pool
 * (rhea.ts `sellRoute`). One pool each; anything else has no route.
 */
export function rheaHops(net: RheaNetwork | undefined, from: string, to: string): { hops: Hop[]; decimalsIn: number; decimalsOut: number; sells?: RheaRoute } | null {
  if (!net) return null;
  const b: RheaRoute | undefined = net.routes[to];
  if (isNear(from)) return b ? { hops: [{ pool: b.pool, tokenIn: net.wrap, tokenOut: b.token }], decimalsIn: NEAR_DECIMALS, decimalsOut: b.decimals } : null;
  const sell = sellRoute(net, from, isNear(to) ? "NEAR" : to);
  if (!sell) return null;
  return { hops: [{ pool: sell.pool, tokenIn: sell.from.token, tokenOut: sell.to.token }], decimalsIn: sell.from.decimals, decimalsOut: sell.to.decimals, sells: sell.from };
}

async function through(poolReturn: PoolReturn, hops: Hop[], amountIn: string): Promise<string> {
  let amount = amountIn;
  for (const h of hops) amount = await poolReturn(h.pool, h.tokenIn, h.tokenOut, amount);
  return amount;
}

/** The order a panel asks for, as the watcher's own grammar (parse.ts). */
export function orderFor(kind: OrderKind, from: string, to: string, amount: string, trigger: string): { symbol: string; direction: "below" | "above"; command: string; line: string } | { problem: string } {
  const f = from.toLowerCase();
  const t = to.toLowerCase();
  const swap = `swap ${amount} ${f} to ${t}`;
  if (kind === "limit" && STABLE.has(from)) {
    if (STABLE.has(to)) return { problem: `A limit order waits for a price. ${from} and ${to} are both dollars.` };
    return { symbol: to, direction: "below", command: `${swap} if ${t} drops below ${trigger}`, line: `Buys ${to} with ${amount} ${from} when ${to} is below $${trigger}.` };
  }
  if (STABLE.has(from)) {
    return { problem: `A ${kind === "stop" ? "stop-loss" : "take profit"} sells a token at a price. Put that token in You pay.` };
  }
  const direction = kind === "stop" ? "below" : "above";
  return {
    symbol: from,
    direction,
    command: `${swap} if ${f} ${direction === "below" ? "drops below" : "goes above"} ${trigger}`,
    line: `Sells ${amount} ${from} for ${to} when ${from} is ${direction} $${trigger}.`,
  };
}

export function quoter(deps: QuoteDeps) {
  const now = deps.now ?? Date.now;
  let fresh: { at: number; value: Promise<{ state: LeashState | null; holdings: { symbol: string; amount: string }[] }> } | null = null;

  /** The leash's state and token balances, shared by quotes a few seconds apart (a re-quote follows every edit). */
  function leash() {
    if (fresh && now() - fresh.at < STATE_FRESH_MS) return fresh.value;
    const value = Promise.all([deps.chain.state().catch(() => null), deps.rhea ? deps.rhea.holdings(deps.cfg.leash).catch(() => []) : Promise.resolve([])]).then(([state, holdings]) => ({ state, holdings }));
    fresh = { at: now(), value };
    value.then((v) => {
      if (!v.state && fresh?.value === value) fresh = null; // a failed read isn't kept
    });
    return value;
  }

  function token(list: IntentsToken[], symbol: string, side: "from" | "to"): { q: QuoteToken; token?: IntentsToken; reason: string } {
    const check = pickToken(list, symbol, side);
    return {
      q: { symbol, assetId: check.token?.assetId ?? null, price: typeof check.token?.price === "number" ? check.token.price : null, verified: check.verified },
      token: check.token,
      reason: check.reason,
    };
  }

  async function quote(ask: { from: string; to: string; amount: string; order?: OrderKind; trigger?: string }): Promise<TradeQuote> {
    const from = ask.from.replace(/^\$/, "").toUpperCase() === "WNEAR" ? "NEAR" : ask.from.replace(/^\$/, "").toUpperCase();
    const to = ask.to.replace(/^\$/, "").toUpperCase() === "WNEAR" ? "NEAR" : ask.to.replace(/^\$/, "").toUpperCase();
    const symbol = /^[A-Z][A-Z0-9]{1,9}$/;
    if (!symbol.test(from) || !symbol.test(to)) throw new QuoteError("Send ?from=NEAR&to=USDC&amount=0.5");
    if (from === to) throw new QuoteError("Pick two different tokens.");
    if (!/^\d+(\.\d+)?$/.test(ask.amount) || !(Number(ask.amount) > 0)) throw new QuoteError("Send an amount, like 0.5");
    if (!deps.intents) throw new QuoteError("Token checks aren't set up on this server", 501);
    // "0.50" and "0.5" are the same trade; the command carries the short one.
    const amount = ask.amount.includes(".") ? ask.amount.replace(/0+$/, "").replace(/\.$/, "") : String(BigInt(ask.amount));
    if (ask.order && !/^\d+(\.\d+)?$/.test(ask.trigger ?? "")) throw new QuoteError("Send a trigger price, like 2.5");

    let list: IntentsToken[];
    try {
      list = await deps.intents.tokens();
    } catch (e) {
      throw new QuoteError(`NEAR Intents didn't answer: ${String((e as Error).message ?? e).slice(0, 160)}`, 502);
    }
    const a = token(list, from, "from");
    const b = token(list, to, "to");
    if (!a.q.verified || !b.q.verified) throw new QuoteError(`Token check failed: ${!a.q.verified ? a.reason : b.reason}.`, 404);
    const nearPrice = pickToken(list, "NEAR", "from").token?.price;

    const net = deps.rhea?.network;
    const path = deps.poolReturn ? rheaHops(net, from, to) : null;
    const leashNow = timeout(leash(), STATE_WAIT_MS);

    let amountOut: number;
    let minReceived: number;
    let route: TradeQuote["route"];
    let priceImpact: number | null = null;
    let valueUsdN: number | null = a.q.price !== null ? Number(amount) * a.q.price : null;
    let executable: boolean;
    let reason: string | null = null;

    if (path) {
      let unitsIn: string;
      try {
        unitsIn = toUnits(amount, path.decimalsIn);
      } catch (e) {
        throw new QuoteError((e as Error).message);
      }
      // The same pools at a thousandth of the size: what the trade would pay if its size moved nothing.
      const small = (BigInt(unitsIn) / 1000n || 1n).toString();
      let out: string;
      let outSmall: string | null;
      let tokenCap: { max_per_trade: string } | null = null;
      try {
        [out, outSmall, tokenCap] = await Promise.all([
          through(deps.poolReturn!, path.hops, unitsIn),
          through(deps.poolReturn!, path.hops, small).catch(() => null),
          path.sells && deps.chain.tokenCap ? timeout(deps.chain.tokenCap(path.sells.token), STATE_WAIT_MS) : Promise.resolve(null),
        ]);
      } catch (e) {
        throw new QuoteError(`Rhea couldn't price ${amount} ${from} → ${to}: ${String((e as Error).message ?? e).slice(0, 160)}`, 502);
      }
      if (BigInt(out) <= 0n) throw new QuoteError(`${amount} ${from} is too small for Rhea's pool to fill.`);
      amountOut = unitsToNumber(out, path.decimalsOut);
      minReceived = unitsToNumber(minOut(out), path.decimalsOut);
      route = { venue: "Rhea", pool: path.hops[0]!.pool, pools: path.hops.map((h) => h.pool) };
      if (outSmall && BigInt(outSmall) > 0n) {
        const here = Number(BigInt(out)) / Number(BigInt(unitsIn));
        const marginal = Number(BigInt(outSmall)) / Number(BigInt(small));
        priceImpact = Math.max(0, Number(((1 - here / marginal) * 100).toFixed(2)));
      }
      executable = true;
      // Selling a token needs the owner's rule for it on the leash; without one the hold would only quote.
      if (path.sells && !tokenCap) {
        executable = false;
        reason = `The leash can't sell ${from} yet. Its owner sets that up; this is Rhea's live quote.`;
      } else if (path.sells && tokenCap && BigInt(unitsIn) > BigInt(tokenCap.max_per_trade)) {
        executable = false;
        reason = `Over your limit of ${tidy(unitsToNumber(tokenCap.max_per_trade, path.decimalsIn))} ${from} a trade.`;
      }
    } else {
      // No pool here: NEAR Intents' own dry quote, which is live mainnet pricing.
      const q = await timeout(deps.intents.quote(a.token!, b.token!, amount), INTENTS_WAIT_MS);
      if (!q) throw new QuoteError(`NEAR Intents couldn't quote ${amount} ${from} → ${to} right now.`, 502);
      amountOut = Number(q.amountOutFormatted);
      minReceived = q.minAmountOut ? unitsToNumber(q.minAmountOut, b.token!.decimals) : amountOut * 0.99;
      route = { venue: "NEAR Intents", seconds: q.timeEstimate ?? null };
      if (q.amountInUsd) valueUsdN = Number(q.amountInUsd);
      if (q.amountInUsd && q.amountOutUsd && Number(q.amountInUsd) > 0) {
        priceImpact = Math.max(0, Number(((1 - Number(q.amountOutUsd) / Number(q.amountInUsd)) * 100).toFixed(2)));
      }
      // Mainnet: NEAR into anything listed runs through a 1Click deposit from the leash.
      executable = deps.cfg.network === "mainnet" && isNear(from);
      if (!executable) {
        const missing = net ? [from, to].filter((s) => !isNear(s) && !net.routes[s]) : [];
        reason =
          deps.cfg.network === "mainnet"
            ? `AIRKEY swaps from NEAR. This is NEAR Intents' live quote for ${from}; nothing would be sent.`
            : `Testnet has no ${missing.join(" or ") || to}. This is NEAR Intents' live mainnet quote; nothing would be sent.`;
      } else if (valueUsdN !== null && valueUsdN > deps.cfg.mainnetUsdCap) {
        executable = false;
        reason = `On mainnet AIRKEY swaps at most $${deps.cfg.mainnetUsdCap}; this is about $${usd(valueUsdN)}.`;
      }
    }

    const vsMarket =
      a.q.price !== null && b.q.price !== null && a.q.price > 0
        ? Number((((amountOut * b.q.price) / (Number(amount) * a.q.price) - 1) * 100).toFixed(2))
        : null;

    // The Trading Agent's caps and the leash's balance, as the chain has them.
    const l = await leashNow;
    const state = l?.state ?? null;
    const valueNear = isNear(from) ? Number(amount) : valueUsdN !== null && nearPrice ? valueUsdN / nearPrice : null;
    let caps: TradeQuote["caps"] = null;
    let balance: TradeQuote["balance"] = null;
    if (state) {
      const agent = state.agents.some((x) => x.account === deps.cfg.agents.trade) ? deps.cfg.agents.trade : deps.cfg.agents.trusted;
      const v = state.agents.find((x) => x.account === agent)?.agent;
      if (v) {
        const perTrade = yoctoToNear(BigInt(v.per_payment_cap));
        const left = Math.max(0, yoctoToNear(BigInt(v.daily_cap) - BigInt(v.spent_today)));
        const within = !state.paused && valueNear !== null && valueNear <= perTrade && valueNear <= left;
        caps = { agent, perTrade: String(perTrade), leftToday: String(left), paused: state.paused, valueNear: valueNear === null ? null : tidy(valueNear), within };
      }
      const held = isNear(from) ? yoctoToNear(BigInt(state.available)) : Number(l?.holdings.find((h) => h.symbol.toUpperCase() === from)?.amount ?? NaN);
      if (Number.isFinite(held)) balance = { symbol: from, amount: tidy(held), enough: held >= Number(amount) };
    }

    const swapCommand = `swap ${amount} ${from.toLowerCase()} to ${to.toLowerCase()}`;
    let command = swapCommand;
    let order: TradeQuote["order"];
    let problem: string | null = executable ? null : reason;
    const overTrade = caps && valueNear !== null && valueNear > Number(caps.perTrade);
    if (!problem && caps?.paused) problem = "The kill switch is on. Nothing trades until you turn it off.";
    if (!problem && overTrade) problem = `Over your ${caps!.perTrade} NEAR per-trade limit: this is worth about ${tidy(valueNear!)} NEAR.`;

    if (ask.order) {
      const trigger = ask.trigger!.includes(".") ? ask.trigger!.replace(/0+$/, "").replace(/\.$/, "") : String(BigInt(ask.trigger!));
      const o = orderFor(ask.order, from, to, amount, trigger);
      if ("problem" in o) {
        problem = problem ?? o.problem;
      } else {
        const watched = o.symbol === from ? a.q.price : b.q.price;
        command = o.command;
        order = { kind: ask.order, symbol: o.symbol, direction: o.direction, trigger, now: watched, line: o.line };
        const t = Number(trigger);
        if (!problem && watched === null) problem = `NEAR Intents has no price for ${o.symbol} right now.`;
        if (!problem && !(t > 0)) problem = "Set a trigger price.";
        if (!problem && watched !== null && (o.direction === "below" ? watched <= t : watched >= t)) {
          problem = `${o.symbol} is already ${o.direction} $${trigger} (now $${usd(watched)}), so this would run right away. Use Swap.`;
        }
      }
    } else {
      if (!problem && caps && !caps.within) problem = `Only ${caps.leftToday} NEAR is left of today's limit; this is worth about ${valueNear === null ? "more" : tidy(valueNear)} NEAR.`;
      if (!problem && balance && !balance.enough) problem = `Not enough ${from}: the leash holds ${balance.amount}.`;
    }

    const feeUsd = nearPrice ? usd(Number(SWAP_FEE_NEAR) * nearPrice) : null;
    return {
      from: a.q,
      to: b.q,
      amountIn: amount,
      amountOut: tidy(amountOut),
      rate: `1 ${from} = ${tidy(amountOut / Number(amount))} ${to}`,
      minReceived: tidy(minReceived),
      slippagePct: 1,
      route,
      executable,
      reason,
      networkFee: { amount: SWAP_FEE_NEAR, symbol: "NEAR", usd: feeUsd },
      priceImpact,
      vsMarket,
      valueUsd: valueUsdN === null ? null : usd(valueUsdN),
      caps,
      balance,
      command,
      problem,
      ready: problem === null && executable && (ask.order ? order !== undefined : true),
      ...(order ? { order } : {}),
    };
  }

  /** The token picker: what trades here first, then NEAR Intents' list in its own order, with the leash's balances. */
  async function tokens(limit = 40): Promise<{ tokens: PickerToken[]; source: string }> {
    if (!deps.intents) throw new QuoteError("Tokens aren't set up on this server", 501);
    let list: IntentsToken[];
    try {
      list = await deps.intents.tokens();
    } catch (e) {
      throw new QuoteError(`NEAR Intents didn't answer: ${String((e as Error).message ?? e).slice(0, 160)}`, 502);
    }
    const l = await timeout(leash(), STATE_WAIT_MS);
    const net = deps.rhea?.network;
    const held = new Map<string, string>();
    if (l?.state) held.set("NEAR", tidy(yoctoToNear(BigInt(l.state.available))));
    for (const h of l?.holdings ?? []) held.set(h.symbol.toUpperCase(), tidy(Number(h.amount)));

    const order = ["NEAR", ...(net ? Object.keys(net.routes) : []), ...held.keys(), ...list.map((t) => (t.symbol.toUpperCase() === "WNEAR" ? "NEAR" : t.symbol.toUpperCase()))];
    const out: PickerToken[] = [];
    const seen = new Set<string>();
    for (const symbol of order) {
      if (seen.has(symbol)) continue;
      seen.add(symbol);
      const check = pickToken(list, symbol, "to");
      if (!check.verified || !check.token) continue;
      const tradable = deps.cfg.network === "mainnet" || isNear(symbol) || !!net?.routes[symbol];
      // A listed token with no price can't be valued against the caps: leave it out unless the leash holds it.
      if (!(check.token.price && check.token.price > 0) && !held.has(symbol) && !tradable) continue;
      out.push({ symbol, chain: check.token.blockchain, price: typeof check.token.price === "number" ? check.token.price : null, balance: held.get(symbol) ?? null, tradable });
      if (out.length >= limit) break;
    }
    return { tokens: out, source: "NEAR Intents" };
  }

  return { quote, tokens };
}

/** The pools' view for this network, or nothing where Rhea isn't used. */
export function poolReturnFor(network: string, rpc: string): PoolReturn | undefined {
  const net = RHEA[network];
  return net ? rheaPoolReturn(rpc, net.exchange) : undefined;
}
