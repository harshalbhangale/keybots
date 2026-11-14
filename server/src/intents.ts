// NEAR Intents (1Click API): token verification and swap quotes.
//
// Token check: a symbol counts as verified only if NEAR Intents itself lists it
// (GET /v0/tokens). We pick the asset on a known home chain, so "SOL" means SOL
// on Solana, never a look-alike listed somewhere else.
//
// Quotes are dry runs ("dry": true): 1Click prices the route and returns what
// you'd get, but nothing is deposited, signed or sent.
//
// A live quote ("dry": false) is a swap for real: 1Click answers with a deposit
// address on NEAR, and sending the input there starts it. The output goes to
// the recipient, a failed swap is refunded on NEAR, and `status` follows it.
// NEAR Intents has no testnet, so a live swap is mainnet and real funds.

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

/** A quote that can be executed: send `amountIn` of the input to `depositAddress`. */
export interface LiveQuote extends Omit<SwapQuote, "dry"> {
  dry: false;
  depositAddress: string;
  depositMemo?: string;
  deadline?: string;
}

export type SwapStatus = "KNOWN_DEPOSIT_TX" | "PENDING_DEPOSIT" | "INCOMPLETE_DEPOSIT" | "PROCESSING" | "SUCCESS" | "REFUNDED" | "FAILED";

/** Where a live swap stands, from GET /v0/status. */
export interface SwapProgress {
  status: SwapStatus;
  /** Finished one way or the other: nothing more will happen. */
  done: boolean;
  amountOutFormatted?: string;
  /** Explorer links 1Click reports for the deposit and the payout. */
  txs: string[];
}

const FINAL: SwapStatus[] = ["SUCCESS", "REFUNDED", "FAILED"];

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

  async function post<T>(path: string, body: unknown): Promise<T> {
    const r = await f(`${base}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(opts.jwt ? { "x-api-key": opts.jwt } : {}) },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    const j = (await r.json().catch(() => ({}))) as T & { message?: string };
    if (!r.ok) throw new Error(j.message ?? `NEAR Intents answered ${r.status}`);
    return j;
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
    const j = await post<{ quote?: Omit<SwapQuote, "dry"> }>("/quote", body);
    if (!j.quote) throw new Error("NEAR Intents sent no quote");
    return { dry: true, ...pickQuote(j.quote) };
  }

  /**
   * A quote to execute. The input is paid from NEAR (`refundTo` gets it back
   * if the swap fails); the output goes to `recipient` on NEAR when the token
   * lives there, otherwise into that account inside NEAR Intents.
   */
  async function liveQuote(from: IntentsToken, to: IntentsToken, amount: string, who: { refundTo: string; recipient: string }): Promise<LiveQuote> {
    const body = {
      dry: false,
      swapType: "EXACT_INPUT",
      slippageTolerance: 100,
      originAsset: from.assetId,
      depositType: "ORIGIN_CHAIN",
      destinationAsset: to.assetId,
      amount: toUnits(amount, from.decimals),
      refundTo: who.refundTo,
      refundType: "ORIGIN_CHAIN",
      recipient: who.recipient,
      recipientType: to.blockchain === "near" ? "DESTINATION_CHAIN" : "INTENTS",
      deadline: new Date(Date.now() + 10 * 60_000).toISOString(),
    };
    const j = await post<{ quote?: Omit<LiveQuote, "dry"> }>("/quote", body);
    if (!j.quote?.depositAddress) throw new Error("NEAR Intents gave no deposit address");
    return { dry: false, ...pickQuote(j.quote), depositAddress: j.quote.depositAddress, depositMemo: j.quote.depositMemo, deadline: j.quote.deadline };
  }

  /** Tell 1Click the deposit went out, so it doesn't wait to notice. */
  async function submitDeposit(txHash: string, depositAddress: string): Promise<void> {
    await post("/deposit/submit", { txHash, depositAddress });
  }

  /** Where a live swap stands. */
  async function status(depositAddress: string): Promise<SwapProgress> {
    const r = await f(`${base}/status?depositAddress=${encodeURIComponent(depositAddress)}`, {
      headers: opts.jwt ? { "x-api-key": opts.jwt } : {},
      signal: AbortSignal.timeout(10_000),
    });
    const j = (await r.json().catch(() => ({}))) as {
      status?: SwapStatus;
      message?: string;
      swapDetails?: { amountOutFormatted?: string; originChainTxHashes?: { explorerUrl?: string }[]; destinationChainTxHashes?: { explorerUrl?: string }[] };
    };
    if (!r.ok || !j.status) throw new Error(j.message ?? `NEAR Intents answered ${r.status}`);
    const d = j.swapDetails ?? {};
    const txs = [...(d.originChainTxHashes ?? []), ...(d.destinationChainTxHashes ?? [])].map((t) => t.explorerUrl).filter((u): u is string => !!u);
    return { status: j.status, done: FINAL.includes(j.status), amountOutFormatted: d.amountOutFormatted, txs };
  }

  /** A token's dollar price on its home chain, or undefined if it isn't listed or has none. */
  async function price(symbol: string, maxAgeMs?: number): Promise<number | undefined> {
    const check = pickToken(await tokens(maxAgeMs), symbol, "to");
    return check.verified ? check.token?.price : undefined;
  }

  return { tokens, quote, liveQuote, submitDeposit, status, price, pick: async (asked: string, side: "from" | "to") => pickToken(await tokens(), asked, side) };
}

export type IntentsClient = ReturnType<typeof intentsClient>;

/** The fields AIRKEY keeps from a 1Click quote. */
function pickQuote(q: Omit<SwapQuote, "dry">) {
  return {
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

/**
 * Where a NEAR Intents buy lands. The 1Click quote names the owner as the
 * recipient: a NEAR token goes straight to the owner's NEAR account; a token
 * from another chain (SOL, BTC) stays in the owner's NEAR Intents balance,
 * which the owner sees and withdraws at app.near-intents.org.
 */
export function intentsLanding(owner: string, blockchain: string | undefined): string {
  return blockchain === "near"
    ? `It lands in ${owner}, your NEAR account.`
    : `It lands in ${owner}'s NEAR Intents balance${blockchain ? ` (${blockchain} tokens stay there until you withdraw them at app.near-intents.org)` : ""}.`;
}
