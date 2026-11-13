// A crypto call someone else posted ("$NEAR breakout, loading up 🚀"),
// copied into the keyboard. Read with fixed rules, no model (Kall Markets'
// heuristic classifier, ported for NEAR), then turned into one small trade
// the owner can hold to run: never run by itself, token checked on NEAR
// Intents, and sized under the Trading Agent's caps as the leash has them.
import type { IntentsClient } from "./intents.js";
import type { LeashState } from "./near.js";

export interface Call {
  isCall: boolean;
  confidence: "low" | "medium" | "high";
  /** The ticker the call is about, upper case ("NEAR"). */
  asset: string | null;
  direction: "bullish" | "bearish" | null;
  /** "perp" only when the post says leverage, longs, shorts or perps. */
  instrument: "spot" | "perp" | null;
  leverage: number | null;
  summary: string;
}

export type CallRoute =
  | {
      status: "available";
      side: "buy" | "sell";
      /** The exact command a hold sends, as if typed. Small on purpose: it's there to be edited. */
      command: string;
      title: string;
      token: { symbol: string; assetId: string; price?: number };
      caps: { agent: string; perTrade: string; leftToday: string; paused: boolean } | null;
      note: string;
    }
  | { status: "unavailable"; reason: string };

/** Dollars a prefilled trade spends: well under the Trading Agent's 1 NEAR a trade. */
export const CALL_SIZE_USD = 2;

const names: Record<string, string> = {
  near: "NEAR", "near protocol": "NEAR", aurora: "AURORA", bitcoin: "BTC", btc: "BTC",
  ethereum: "ETH", eth: "ETH", ether: "ETH", solana: "SOL", sol: "SOL", doge: "DOGE", dogecoin: "DOGE",
};
/** Dollars aren't a call: "$5" is an amount, USDC is cash. */
const notAssets = new Set(["USD", "USDC", "USDT", "DAI"]);

const bullish =
  /\b(buy|buying|bought|long(?:ing)?|bullish|moon(?:ing)?|pump(?:ing)?|send(?:ing)? it|accumulat\w*|ape\w*|breakout|higher|load(?:ing)? up|undervalued|bid(?:ding)?|strong|bottom is in)\b|📈|🚀/i;
const bearish =
  /\b(sell|selling|sold|short(?:ing)?|bearish|dump(?:ing)?|top is in|exit(?:ing)?|lower|overvalued|rug\w*|fade|weak|i'?m out|taking profits?)\b|📉/i;
// "go long", "short ETH", perps, futures, leverage or "10x" mean a perp position;
// "long term" / "short-term" / "long run" describe a horizon, not a position.
const perpCue =
  /\b(long|short|longs|shorts|longing|shorting)\b(?![\s-]*(?:term|run)\b)|\b(perps?|perpetuals?|futures|leverage[d]?)\b|\b([1-9][0-9]{0,2})\s?x\b/i;
const tradeCue = /\b(trade|trading|entry|target|tp|sl|stop loss)\b/i;
// A contract address in the post: the ticker can't be trusted to mean that token.
const contract = /\b0x[a-fA-F0-9]{40}\b|\b[1-9A-HJ-NP-Za-km-z]{32,44}\b/;

function findAsset(text: string): string | null {
  for (const m of text.matchAll(/\$([A-Za-z][A-Za-z0-9]{1,9})\b/g)) {
    const s = m[1]!.toUpperCase();
    if (!notAssets.has(s)) return s;
  }
  if (/near protocol/i.test(text)) return "NEAR";
  for (const word of text.match(/[A-Za-z]+/g) ?? []) {
    const lower = word.toLowerCase();
    // "near" is an English word ("near the top"): only NEAR in capitals is the token.
    if (lower === "near" && word !== "NEAR") continue;
    if (names[lower]) return names[lower]!;
  }
  return null;
}

/** Fixed rules, no model. Conservative: mixed cues lower the confidence. */
export function readCall(text: string): Call {
  const asset = findAsset(text);
  // "in the short term" / "long run" are horizons, not a long or short call.
  const directional = text.replace(/\b(?:long|short)[\s-]*(?:term|run)\b/gi, " ");
  const up = bullish.test(directional);
  const down = bearish.test(directional);
  const direction = up && !down ? "bullish" : down && !up ? "bearish" : null;
  const perp = perpCue.test(text);
  const lev = text.match(/\b([1-9][0-9]{0,2})\s?x\b/i);
  const isCall = Boolean(asset && (direction || tradeCue.test(text)));
  const explicitVerb = /\b(buy(?:ing)?|bought|sell(?:ing)?|sold|long(?:ing)?|short(?:ing)?)\b/i.test(text);
  const confidence: Call["confidence"] = !isCall ? "low" : up && down ? "low" : explicitVerb && /\$[A-Za-z]/.test(text) ? "high" : "medium";
  const instrument = !isCall ? null : perp ? "perp" : "spot";
  const leverage = instrument === "perp" && lev ? Math.min(Number(lev[1]), 200) : null;
  const word = direction === "bullish" ? "Bullish" : direction === "bearish" ? "Bearish" : "Directionless";
  return {
    isCall,
    confidence,
    asset: isCall ? asset : null,
    direction: isCall ? direction : null,
    instrument,
    leverage,
    summary: isCall
      ? `${word} ${instrument} call on ${asset}${leverage ? ` at ${leverage}x` : ""}.`
      : "Not a trade call: no token with a stated direction.",
  };
}

/**
 * Only what the post says, as one small spot trade from the leash. Bullish
 * buys with NEAR; bearish on NEAR moves it to USDC. Perps, shorts of tokens
 * the leash doesn't hold, and posts with a contract address get no route
 * rather than a stand-in.
 */
export async function routeCall(
  text: string,
  call: Call,
  deps: { intents?: IntentsClient; chain: { state(): Promise<LeashState> }; tradeAgent: string },
): Promise<CallRoute> {
  if (!call.isCall || !call.asset) return { status: "unavailable", reason: "This isn't a trade call." };
  if (contract.test(text)) {
    return { status: "unavailable", reason: "The post names a contract address. Check the token by hand; AIRKEY won't trade a ticker in its place." };
  }
  if (call.instrument === "perp") {
    return { status: "unavailable", reason: `A ${call.leverage ? `${call.leverage}x ` : ""}perp call on ${call.asset}. AIRKEY trades spot through the leash, so there's no stand-in.` };
  }
  if (!call.direction) return { status: "unavailable", reason: `The post names ${call.asset} but doesn't say buy or sell.` };
  if (call.direction === "bearish" && call.asset !== "NEAR") {
    return { status: "unavailable", reason: `Bearish on ${call.asset}. AIRKEY doesn't short, and the leash holds no ${call.asset} to sell.` };
  }
  if (!deps.intents) return { status: "unavailable", reason: "Token checks aren't set up on this server." };

  const check = await deps.intents.pick(call.asset, "to");
  if (!check.verified || !check.token) return { status: "unavailable", reason: `Token check failed: ${check.reason}.` };

  const asset = call.asset.toLowerCase();
  const usd = `$${CALL_SIZE_USD}`;
  const side = call.direction === "bullish" ? "buy" : "sell";
  const command =
    side === "sell" ? `swap ${usd} of near to usdc` : asset === "near" ? `buy ${usd} of near` : `swap ${usd} of near to ${asset}`;
  const title = side === "sell" ? `Sell ${usd} of NEAR for USDC` : `Buy ${usd} of ${call.asset}`;

  let caps: Extract<CallRoute, { status: "available" }>["caps"] = null;
  try {
    const state = await deps.chain.state();
    const a = state.agents.find((x) => x.account === deps.tradeAgent)?.agent;
    if (a) {
      const left = BigInt(a.daily_cap) - BigInt(a.spent_today);
      caps = { agent: deps.tradeAgent, perTrade: near(BigInt(a.per_payment_cap)), leftToday: near(left > 0n ? left : 0n), paused: state.paused };
    }
  } catch {
    // The chip still works without the caps; the leash checks them again on the hold.
  }
  return {
    status: "available",
    side,
    command,
    title,
    token: { symbol: check.token.symbol, assetId: check.token.assetId, price: check.token.price },
    caps,
    note: `From a copied call (${call.confidence}). ${call.asset} is on NEAR Intents. Nothing runs until you hold.`,
  };
}

const near = (yocto: bigint) => String(Number(yocto / 10n ** 18n) / 1e6);
