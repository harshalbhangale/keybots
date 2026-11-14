// Rhea (formerly Ref Finance), NEAR's main exchange: real swaps from the leash.
//
// The leash wraps the NEAR and hands the wNEAR to Rhea with ft_transfer_call;
// Rhea swaps it in one pool and sends the token straight back to the leash.
// The value never leaves the leash, and the swap can't fill below
// `min_amount_out` (1% under the pool's own quote).
//
// Testnet has deep pools for test stablecoins, so a swap there is real and
// on chain but costs nothing. Mainnet uses Rhea's deepest pools for NEAR/USDC
// and NEAR/USDT; anything else NEAR Intents lists goes through NEAR Intents.

export interface RheaRoute {
  /** What people type: "USDT". */
  symbol: string;
  token: string;
  pool: number;
  decimals: number;
}

export interface RheaNetwork {
  exchange: string;
  wrap: string;
  routes: Record<string, RheaRoute>;
  /** Pools that trade two of the tokens above directly, by "A/B" in either order: "USDC/USDT". */
  pairs?: Record<string, number>;
}

/** Selling a token the leash holds: one pool, the token in, NEAR or another token out. */
export interface RheaSell {
  /** The token sold: one of the network's routes. */
  from: RheaRoute;
  /** What comes back: "NEAR" (wNEAR from the pool, unwrapped by the leash) or a token. */
  to: { symbol: string; token: string; decimals: number };
  pool: number;
  /** The output is wNEAR, which the leash turns back into NEAR. */
  unwrap: boolean;
}

/** The pools AIRKEY trades in, chosen for depth (tens of thousands of wNEAR each). */
export const RHEA: Record<string, RheaNetwork | undefined> = {
  testnet: {
    exchange: "ref-finance-101.testnet",
    wrap: "wrap.testnet",
    routes: {
      USDT: { symbol: "USDT", token: "usdt.itachicara.testnet", pool: 1084, decimals: 24 },
      USDC: { symbol: "USDC", token: "usdc.itachicara.testnet", pool: 1103, decimals: 24 },
    },
    // The deepest USDC/USDT pool there (thousands of each).
    pairs: { "USDC/USDT": 1126 },
  },
  // Read on 14 Nov 2026 with view calls on v2.ref-finance.near (get_pools over
  // all 9019 pools, then get_return for 1 NEAR in each candidate):
  //   4512  NEAR/USDC  simple pool, 0.3% fee, ~278,000 wNEAR / ~919,000 USDC   1 NEAR -> 3.299 USDC
  //   6063  NEAR/USDT  degen pool,  0.3% fee, ~49,000 wNEAR / ~163,000 USDT    1 NEAR -> 3.312 USDT
  //   6416  USDC/USDT  degen pool,  0.01% fee, ~282,000 USDC / ~318,000 USDT
  // The next NEAR/USDT pool (3879, a simple pool) holds only ~550 wNEAR. See pickPool below.
  mainnet: {
    exchange: "v2.ref-finance.near",
    wrap: "wrap.near",
    routes: {
      USDC: { symbol: "USDC", token: "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1", pool: 4512, decimals: 6 },
      USDT: { symbol: "USDT", token: "usdt.tether-token.near", pool: 6063, decimals: 6 },
    },
    pairs: { "USDC/USDT": 6416 },
  },
};

/** One pool as Rhea's get_pools lists it. */
export interface RheaPoolInfo {
  token_account_ids: string[];
  amounts: string[];
  pool_kind?: string;
  total_fee?: number;
}

/**
 * The deepest two-token pool for `a`/`b` in a page of get_pools (ids start at
 * `fromIndex`): the one holding the most of `a`. This is how the mainnet pool
 * ids above were chosen; it is kept so they can be checked again.
 */
export function pickPool(pools: RheaPoolInfo[], a: string, b: string, fromIndex = 0): { id: number; depth: bigint } | undefined {
  let best: { id: number; depth: bigint } | undefined;
  pools.forEach((p, i) => {
    const ts = p.token_account_ids;
    if (ts.length !== 2 || !ts.includes(a) || !ts.includes(b)) return;
    const depth = BigInt(p.amounts[ts.indexOf(a)] ?? "0");
    if (!best || depth > best.depth) best = { id: fromIndex + i, depth };
  });
  return best;
}

/** 1% under the quote, in basis points. */
const SLIPPAGE_BPS = 100n;

/** The swap Rhea runs on ft_transfer_call: one pool, NEAR in, the token out. */
export function swapMsg(net: RheaNetwork, route: RheaRoute, amountIn: string, minOut: string): string {
  return JSON.stringify({
    actions: [{ pool_id: route.pool, token_in: net.wrap, token_out: route.token, amount_in: amountIn, min_amount_out: minOut }],
  });
}

/** The swap Rhea runs when the leash sells a token: one pool, the token in, wNEAR or the other token out. */
export function sellMsg(sell: RheaSell, amountIn: string, minOut: string): string {
  return JSON.stringify({
    actions: [{ pool_id: sell.pool, token_in: sell.from.token, token_out: sell.to.token, amount_in: amountIn, min_amount_out: minOut }],
  });
}

/** How AIRKEY sells `from` for `to` on this network, if it can: "USDC" for "NEAR", "USDT" for "USDC". */
export function sellRoute(net: RheaNetwork | undefined, from: string, to: string): RheaSell | undefined {
  const [a, b] = [from.toUpperCase(), to.toUpperCase()];
  const route = net?.routes[a];
  if (!net || !route || a === b) return undefined;
  if (b === "NEAR") return { from: route, to: { symbol: "NEAR", token: net.wrap, decimals: 24 }, pool: route.pool, unwrap: true };
  const out = net.routes[b];
  const pool = net.pairs?.[`${a}/${b}`] ?? net.pairs?.[`${b}/${a}`];
  if (!out || pool === undefined) return undefined;
  return { from: route, to: { symbol: out.symbol, token: out.token, decimals: out.decimals }, pool, unwrap: false };
}

/** "0.5" with 24 decimals -> "500000000000000000000000", exact (no floats). */
export function toUnits(amount: string, decimals: number): string {
  const [i, f = ""] = amount.split(".");
  if (!/^\d+$/.test(i) || !/^\d*$/.test(f) || f.length > decimals) throw new Error("Not an amount");
  return (BigInt(i) * 10n ** BigInt(decimals) + BigInt((f + "0".repeat(decimals)).slice(0, decimals) || "0")).toString();
}

/** The least the swap may return: the pool's quote less the slippage allowance. */
export function minOut(expected: string): string {
  return ((BigInt(expected) * (10_000n - SLIPPAGE_BPS)) / 10_000n).toString();
}

/** What Rhea paid out, from its log line "Swapped 100 wrap.testnet for 124 usdt.itachicara.testnet". */
export function amountOut(logs: string[], token: string): string | undefined {
  for (const l of logs) {
    const m = /Swapped (\d+) ([^\s,]+) for (\d+) ([^\s,]+)/.exec(l);
    if (m && m[4] === token) return m[3];
  }
  return undefined;
}

/** "124112944945096337934249" with 24 decimals -> "0.1241". */
export function fromUnits(units: string, decimals: number): string {
  const v = Number(BigInt(units) * 10_000n / 10n ** BigInt(decimals)) / 10_000;
  return String(v);
}

export function rheaClient(opts: { network: string; rpc: string; fetchImpl?: typeof fetch }) {
  const net = RHEA[opts.network];
  const f = opts.fetchImpl ?? fetch;

  async function view<T>(contract: string, method: string, args: unknown): Promise<T> {
    const r = await f(opts.rpc, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: "airkey",
        method: "query",
        params: { request_type: "call_function", finality: "final", account_id: contract, method_name: method, args_base64: Buffer.from(JSON.stringify(args)).toString("base64") },
      }),
      signal: AbortSignal.timeout(10_000),
    });
    const j = (await r.json()) as { result?: { result?: number[]; error?: string }; error?: { message?: string } };
    if (!j.result?.result) throw new Error(j.result?.error ?? j.error?.message ?? "NEAR RPC didn't answer");
    return JSON.parse(Buffer.from(j.result.result).toString()) as T;
  }

  return {
    network: net,
    /** The route for a token, if AIRKEY can swap NEAR into it here. */
    route: (symbol: string): RheaRoute | undefined => net?.routes[symbol.toUpperCase()],
    /** What `amountIn` yocto of NEAR gets from the pool right now, in the token's units. */
    quote: (route: RheaRoute, amountIn: string) =>
      view<string>(net!.exchange, "get_return", { pool_id: route.pool, token_in: net!.wrap, amount_in: amountIn, token_out: route.token }),
    /** How to sell a token the leash holds for NEAR or for another token here, if AIRKEY can. */
    sellRoute: (from: string, to: string): RheaSell | undefined => sellRoute(net, from, to),
    /** What selling `amountIn` units of the token gets from the pool right now, in the output's units. */
    quoteSell: (sell: RheaSell, amountIn: string) =>
      view<string>(net!.exchange, "get_return", { pool_id: sell.pool, token_in: sell.from.token, amount_in: amountIn, token_out: sell.to.token }),
    /** The tokens `account` holds that AIRKEY trades in (swaps land back in the leash). */
    async holdings(account: string): Promise<{ symbol: string; token: string; amount: string }[]> {
      if (!net) return [];
      const routes = Object.values(net.routes);
      const units = await Promise.all(routes.map((r) => view<string>(r.token, "ft_balance_of", { account_id: account }).catch(() => "0")));
      return routes.map((r, i) => ({ symbol: r.symbol, token: r.token, amount: fromUnits(units[i] ?? "0", r.decimals) }));
    },
  };
}

export type RheaClient = ReturnType<typeof rheaClient>;
