// Rhea (formerly Ref Finance), NEAR's main exchange: real swaps from the leash.
//
// The leash wraps the NEAR and hands the wNEAR to Rhea with ft_transfer_call;
// Rhea swaps it in one pool and sends the token straight back to the leash.
// The value never leaves the leash, and the swap can't fill below
// `min_amount_out` (1% under the pool's own quote).
//
// Testnet has deep pools for test stablecoins, so a swap there is real and
// on chain but costs nothing. On mainnet, AIRKEY swaps through NEAR Intents.

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
  },
};

/** 1% under the quote, in basis points. */
const SLIPPAGE_BPS = 100n;

/** The swap Rhea runs on ft_transfer_call: one pool, NEAR in, the token out. */
export function swapMsg(net: RheaNetwork, route: RheaRoute, amountIn: string, minOut: string): string {
  return JSON.stringify({
    actions: [{ pool_id: route.pool, token_in: net.wrap, token_out: route.token, amount_in: amountIn, min_amount_out: minOut }],
  });
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
  };
}

export type RheaClient = ReturnType<typeof rheaClient>;
