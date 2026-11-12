// Turns a command into an action without any AI: fast, predictable, and the
// same answer every time. Free-form text the rules can't read goes to NEAR AI
// Cloud (src/ai.ts) instead.

export type Action =
  | { kind: "pay"; receiver: string; amountNear: string; memo?: string }
  | { kind: "swap"; amount: string; from: string; to: string }
  /** A trade to run later, when `symbol` crosses `price` (dollars). */
  | { kind: "watch"; command: string; trade: { amount: string; from: string; to: string }; symbol: string; direction: "below" | "above"; price: string }
  | { kind: "unknown"; reason: string };

const VERB = String.raw`(?:pay|send|give|transfer|tip)`;
const AMOUNT = String.raw`(\d+(?:\.\d+)?)`;
const UNIT = String.raw`(?:\s*(?:near|Ⓝ))?`;
// NEAR account ids: lowercase letters, digits, - _ and dots between parts.
const ACCOUNT = String.raw`([a-z0-9_-]+(?:\.[a-z0-9_-]+)*)`;
const MEMO = String.raw`(?:\s+(?:for|re|memo:?)\s+(.+?))?`;

// "send 5 NEAR to drain.near immediately", "pay 0.5 near to harshal for dinner"
const AMOUNT_FIRST = new RegExp(String.raw`\b${VERB}\s+${AMOUNT}${UNIT}\s+(?:to\s+)?${ACCOUNT}${MEMO}\s*[.!?]*$`, "i");
// "Pay harshal.near 0.5 NEAR for dinner"
const RECEIVER_FIRST = new RegExp(String.raw`\b${VERB}\s+${ACCOUNT}\s+${AMOUNT}${UNIT}${MEMO}\s*[.!?]*$`, "i");
// "swap 20 usdc to sol"
const SWAP = new RegExp(String.raw`\bswap\s+${AMOUNT}\s*([a-z][a-z0-9]{1,9})\s+(?:to|for|into)\s+([a-z][a-z0-9]{1,9})\b`, "i");

// "buy $10 of near", "buy 10 usdc of sol": spend dollars (USDC) on a token.
const SYMBOL = String.raw`\$?([a-z][a-z0-9]{1,9})`;
const BUY_DOLLAR = new RegExp(String.raw`\bbuy\s+\$\s*${AMOUNT}\s+(?:worth\s+)?(?:of\s+)?${SYMBOL}\b`, "i");
const BUY_WORDS = new RegExp(String.raw`\bbuy\s+${AMOUNT}\s*(?:usdc?|dollars?|bucks)\s+(?:worth\s+)?(?:of\s+)?${SYMBOL}\b`, "i");
// "sell 5 near", "sell 0.5 near for usdc": sell a token, for USDC unless said.
const SELL = new RegExp(String.raw`\bsell\s+${AMOUNT}\s*${SYMBOL}(?:\s+(?:for|to|into)\s+${SYMBOL})?\b`, "i");
/** What a dollar amount is paid in. */
export const DOLLAR = "USDC";

// "<a trade> if it drops below 2", "<a trade> when near goes above $4"
const WHEN = new RegExp(
  String.raw`^(.+?)\s+(?:if|when|once|whenever)\s+(?:it|the\s+price|\$?[a-z][a-z0-9]{1,9})?\s*(?:drops?|falls?|dips?|goes|is|gets|rises?|climbs?|hits)?\s*(?:to\s+)?(below|under|above|over|past)\s+\$?${AMOUNT}\s*[.!?]*$`,
  "i",
);

const FILLER = new Set(["immediately", "now", "asap", "urgently", "please", "pls", "today", "right", "away"]);

/** Reads the first action in the text. Works line by line so a pasted message can carry other words. */
export function parse(text: string): Action {
  const lines = text
    .replace(/[“”]/g, '"')
    .split(/[\n.!?](?=\s|$)|[\n]/)
    .map((l) => l.trim())
    .filter(Boolean);
  for (const raw of [text.trim(), ...lines]) {
    const line = stripFiller(raw);
    const w = line.match(WHEN);
    if (w) {
      const trade = parse(w[1]);
      if (trade.kind === "swap") {
        // Watch the token being bought or sold, not the dollars on the other side.
        const symbol = trade.from === DOLLAR ? trade.to : trade.from;
        const direction = /below|under/i.test(w[2]) ? "below" : "above";
        return { kind: "watch", command: w[1].trim(), trade: { amount: trade.amount, from: trade.from, to: trade.to }, symbol, direction, price: normaliseAmount(w[3]) };
      }
    }
    const s = line.match(SWAP);
    if (s) return { kind: "swap", amount: s[1], from: s[2].toUpperCase(), to: s[3].toUpperCase() };
    const b = line.match(BUY_DOLLAR) ?? line.match(BUY_WORDS);
    if (b && b[2].toUpperCase() !== DOLLAR) return { kind: "swap", amount: normaliseAmount(b[1]), from: DOLLAR, to: b[2].toUpperCase() };
    const x = line.match(SELL);
    if (x) {
      const to = (x[3] ?? DOLLAR).toUpperCase();
      if (to !== x[2].toUpperCase()) return { kind: "swap", amount: normaliseAmount(x[1]), from: x[2].toUpperCase(), to };
    }
    const a = line.match(AMOUNT_FIRST);
    if (a && !/^\d/.test(a[2])) return pay(a[2], a[1], a[3]);
    const r = line.match(RECEIVER_FIRST);
    if (r && !/^\d+(\.\d+)?$/.test(r[1])) return pay(r[1], r[2], r[3]);
  }
  return { kind: "unknown", reason: "I couldn't find a payment or a swap in that." };
}

function stripFiller(line: string): string {
  const words = line.trim().split(/\s+/);
  while (words.length && FILLER.has(words[words.length - 1].toLowerCase().replace(/[.!?,]+$/, ""))) words.pop();
  return words.join(" ");
}

function pay(receiver: string, amount: string, memo?: string): Action {
  const r = receiver.toLowerCase().replace(/[.,;:]+$/, "");
  const m = memo?.trim().replace(/[.!?]+$/, "");
  return { kind: "pay", receiver: r, amountNear: normaliseAmount(amount), ...(m ? { memo: m.slice(0, 140) } : {}) };
}

function normaliseAmount(a: string): string {
  const [i, f = ""] = a.split(".");
  const frac = f.replace(/0+$/, "");
  return frac ? `${BigInt(i)}.${frac}` : `${BigInt(i)}`;
}

/** NEAR -> yoctoNEAR as a decimal string, exact (no floats). */
export function toYocto(near: string): string {
  const [i, f = ""] = near.split(".");
  if (f.length > 24) throw new Error("Too many decimals");
  return (BigInt(i) * 10n ** 24n + BigInt((f + "0".repeat(24)).slice(0, 24))).toString();
}

const ACCOUNT_RE = /^(([a-z\d]+[-_])*[a-z\d]+\.)*([a-z\d]+[-_])*[a-z\d]+$/;

/** Resolves a name through the address book, or accepts a full account id on this network. */
export function resolveReceiver(
  name: string,
  contacts: Record<string, string>,
  network: "testnet" | "mainnet",
): { account: string; via: "contacts" | "account" } | { error: string } {
  const key = name.toLowerCase();
  if (contacts[key]) return { account: contacts[key], via: "contacts" };
  const suffix = network === "mainnet" ? ".near" : ".testnet";
  const implicit = /^[0-9a-f]{64}$/.test(key);
  if (implicit || (key.endsWith(suffix) && ACCOUNT_RE.test(key) && key.length <= 64)) return { account: key, via: "account" };
  if (key.includes(".")) return { error: `${name} isn't a ${network} account, and it isn't in your contacts.` };
  return { error: `Who is ${name}? Add them to your contacts first.` };
}
