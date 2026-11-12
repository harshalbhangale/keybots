// NEAR Intents (1Click API): token verification and swap quotes.
//
// Token check: a symbol counts as verified only if NEAR Intents itself lists it
// (GET /v0/tokens). We pick the asset on a known home chain, so "SOL" means SOL
// on Solana, never a look-alike listed somewhere else.
//
// Quotes are dry runs ("dry": true): 1Click prices the route and returns what
// you'd get, but nothing is deposited, signed or sent. NEAR Intents has no
// testnet, so executing a swap means mainnet and real funds; that waits for the
// owner's explicit go-ahead.

export const ONE_CLICK = "https://1click.chaindefuser.com/v0";

export interface IntentsToken {
  assetId: string;
  symbol: string;
  blockchain: string;
  decimals: number;
  price?: number;
  contractAddress?: string | null;
}

export interface TokenCheck {
  asked: string;
  verified: boolean;
  token?: IntentsToken;
  /** Other chains the same symbol is listed on (not chosen). */
  alsoOn: string[];
  reason: string;
}

export interface SwapQuote {
  dry: true;
  amountIn: string;
  amountInFormatted: string;
  amountInUsd?: string;
  amountOut: string;
  amountOutFormatted: string;
  amountOutUsd?: string;
  minAmountOut?: string;
  timeEstimate?: number;
}

/** Where each symbol "lives". Anything else defaults to NEAR, where the leash holds funds. */
const HOME: Record<string, string> = {
  SOL: "sol",
  BTC: "btc",
  ETH: "eth",
  ZEC: "zec",
  DOGE: "doge",
  XRP: "xrp",
  TRX: "tron",
  BNB: "bsc",
  ADA: "cardano",
  SUI: "sui",
  APT: "aptos",
  TON: "ton",
  NEAR: "near",
  WNEAR: "near",
};
/** What people type vs. what NEAR Intents calls it. */
const ALIAS: Record<string, string> = { NEAR: "WNEAR" };

export function pickToken(list: IntentsToken[], asked: string, side: "from" | "to"): TokenCheck {
  const sym = asked.toUpperCase();
  const listed = list.filter((t) => t.symbol.toUpperCase() === (ALIAS[sym] ?? sym));
  if (listed.length === 0) {
    return { asked, verified: false, alsoOn: [], reason: `${asked.toUpperCase()} isn't on NEAR Intents' list of ${list.length} supported assets` };
  }
  // You pay from NEAR (where the leash is); you receive on the token's home chain.
  const want = side === "from" ? "near" : (HOME[sym] ?? "near");
  const token = listed.find((t) => t.blockchain === want) ?? (listed.length === 1 ? listed[0] : undefined);
  const alsoOn = listed.filter((t) => t !== token).map((t) => t.blockchain);
  if (!token) {
    return { asked, verified: false, alsoOn, reason: `${sym} is listed on ${alsoOn.join(", ")}; say which chain` };
  }
  return { asked, verified: true, token, alsoOn, reason: `Listed by NEAR Intents on ${token.blockchain} (${token.assetId})` };
}

/** "20.5" with 6 decimals -> "20500000". Exact, no floats. */
export function toUnits(amount: string, decimals: number): string {
  if (!/^\d+(\.\d+)?$/.test(amount)) throw new Error(`${amount} isn't an amount`);
  const [i, f = ""] = amount.split(".");
  if (f.length > decimals) throw new Error(`Too many decimals for this token (max ${decimals})`);
  return (BigInt(i) * 10n ** BigInt(decimals) + BigInt((f + "0".repeat(decimals)).slice(0, decimals) || "0")).toString();
}

export function intentsClient(opts: { jwt?: string; recipient: string; fetchImpl?: typeof fetch; base?: string }) {
  const f = opts.fetchImpl ?? fetch;
  const base = opts.base ?? ONE_CLICK;
  let cache: { at: number; list: IntentsToken[] } | null = null;

  /** The token list, at most `maxAgeMs` old (five minutes unless said). */
  async function tokens(maxAgeMs = 5 * 60_000): Promise<IntentsToken[]> {
    if (cache && Date.now() - cache.at < maxAgeMs) return cache.list;
    const r = await f(`${base}/tokens`, { signal: AbortSignal.timeout(10_000) });
    if (!r.ok) throw new Error(`NEAR Intents token list answered ${r.status}`);
    cache = { at: Date.now(), list: (await r.json()) as IntentsToken[] };
    return cache.list;
  }

  async function quote(from: IntentsToken, to: IntentsToken, amount: string): Promise<SwapQuote> {
    const body = {
      dry: true,
      swapType: "EXACT_INPUT",
      slippageTolerance: 100,
      originAsset: from.assetId,
      depositType: "INTENTS",
      destinationAsset: to.assetId,
      amount: toUnits(amount, from.decimals),
      recipient: opts.recipient,
      recipientType: "INTENTS",
      refundTo: opts.recipient,
      refundType: "INTENTS",
      deadline: new Date(Date.now() + 5 * 60_000).toISOString(),
    };
    const r = await f(`${base}/quote`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(opts.jwt ? { "x-api-key": opts.jwt } : {}) },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    const j = (await r.json()) as { quote?: Omit<SwapQuote, "dry">; message?: string };
    if (!r.ok || !j.quote) throw new Error(j.message ?? `NEAR Intents answered ${r.status}`);
    const q = j.quote;
    return {
      dry: true,
      amountIn: q.amountIn,
      amountInFormatted: q.amountInFormatted,
      amountInUsd: q.amountInUsd,
      amountOut: q.amountOut,
      amountOutFormatted: q.amountOutFormatted,
      amountOutUsd: q.amountOutUsd,
      minAmountOut: q.minAmountOut,
      timeEstimate: q.timeEstimate,
    };
  }

  /** A token's dollar price on its home chain, or undefined if it isn't listed or has none. */
  async function price(symbol: string, maxAgeMs?: number): Promise<number | undefined> {
    const check = pickToken(await tokens(maxAgeMs), symbol, "to");
    return check.verified ? check.token?.price : undefined;
  }

  return { tokens, quote, price, pick: async (asked: string, side: "from" | "to") => pickToken(await tokens(), asked, side) };
}

export type IntentsClient = ReturnType<typeof intentsClient>;
