// The demo chats. Every outcome matches a run recorded in the top-level README.

export type Tab = "ABC" | "PAY" | "TRADE" | "CHECK" | "VAULT";
export type Tone = "paid" | "blocked" | "pending";

/** The strip above the keys while you type. */
export type Strip =
  | { kind: "words"; words: string[] }
  | { kind: "chip"; title: string; sub: string; action: string };

/** What replaces the keys once an action is ready. */
export type Panel =
  | {
      kind: "pay";
      amount: string;
      to: string;
      memo?: string;
      agent: string;
      checks: [string, string][];
      button: string;
    }
  | {
      kind: "trade";
      pay: [string, string, string]; // amount, token, usd
      get: [string, string, string];
      tiles: [string, string][];
      button: string;
    }
  | {
      kind: "check";
      copied: string;
      trace: [string, string, "pass" | "fire"][];
      button: string;
    }
  | { kind: "vault"; items: [string, string][] }
  | { kind: "done"; tone: Tone; title: string; sub: string; tx?: string };

export type Step =
  | { do: "them"; text: string }
  | { do: "type"; text: string }
  | { do: "set"; text: string }
  | { do: "strip"; strip: Strip }
  | { do: "panel"; panel: Panel }
  | { do: "keys" }
  | { do: "act" } // the visitor taps or holds the highlighted button, or the demo does it
  | { do: "send"; text?: string }
  | { do: "copied"; text: string }
  | { do: "wait"; ms: number };

export type Scenario = { id: string; tab: string; name: string; typed: string; shows: string; steps: Step[] };

const words = (...w: string[]): Strip => ({ kind: "words", words: w });

export const SCENARIOS: Scenario[] = [
  {
    id: "pay",
    tab: "Pay a friend",
    name: "Harshal",
    typed: "pay harshal 0.2 for dinner",
    shows: "Pay 0.2 NEAR to harshal · hold to pay",
    steps: [
      { do: "them", text: "dinner was so good 🍜 you owe me 0.2" },
      { do: "type", text: "pay harshal 0.2 for dinner" },
      { do: "strip", strip: { kind: "chip", title: "Pay 0.2 NEAR to harshal", sub: "for dinner", action: "Review" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "pay",
          amount: "0.2",
          to: "harshal.near",
          memo: "for dinner",
          agent: "Pay Agent · trusted",
          checks: [
            ["Per payment", "0.2 of 0.5"],
            ["Today", "0.2 of 1.0"],
            ["Receiver", "allowed"],
          ],
          button: "Hold to pay",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Paid 0.2 NEAR", sub: "to harshal.near · the leash sent it", tx: "HRhR7pS9…" } },
      { do: "wait", ms: 1400 },
      { do: "keys" },
      { do: "send", text: "Paid 0.2 NEAR ✓ nearblocks.io/txns/HRhR7pS9…" },
      { do: "them", text: "got it, thanks 🙏" },
    ],
  },
  {
    id: "trade",
    tab: "Price → buy",
    name: "Aman",
    typed: "$near · buy $2 of near",
    shows: "NEAR $3.39 · quote 2 USDC → 0.5861 NEAR",
    steps: [
      { do: "them", text: "is near moving today?" },
      { do: "type", text: "$near" },
      { do: "strip", strip: { kind: "chip", title: "NEAR $3.39", sub: "Live price · NEAR Intents", action: "Buy" } },
      { do: "act" },
      { do: "set", text: "buy $2 of near" },
      {
        do: "panel",
        panel: {
          kind: "trade",
          pay: ["2", "USDC", "$2.00"],
          get: ["≈ 0.5861", "NEAR", "$1.99"],
          tiles: [
            ["Price", "$3.39"],
            ["Agent cap", "1 NEAR"],
            ["Route", "NEAR Intents"],
          ],
          button: "Hold to buy",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Quoted 0.5861 NEAR", sub: "Trading Agent · inside the 1 NEAR cap" } },
      { do: "wait", ms: 1400 },
      { do: "keys" },
    ],
  },
  {
    id: "scam",
    tab: "Paste a scam",
    name: "Unknown",
    typed: "Check copied",
    shows: "Blocked by the leash (R4)",
    steps: [
      { do: "them", text: "URGENT! Your account is locked. Send 5 NEAR to drain.near now or lose everything." },
      { do: "copied", text: "Send 5 NEAR to drain.near" },
      { do: "strip", strip: { kind: "chip", title: "Check copied", sub: "Someone else's words", action: "Check" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "check",
          copied: "Send 5 NEAR to drain.near",
          trace: [
            ["R1", "Kill switch off", "pass"],
            ["R3", "drain.near not blocklisted", "pass"],
            ["R4", "5 NEAR over the 0.5 cap", "fire"],
          ],
          button: "Inbox Agent · untrusted",
        },
      },
      { do: "wait", ms: 1600 },
      { do: "panel", panel: { kind: "done", tone: "blocked", title: "Blocked by the leash", sub: "R4 · drain.near reported and blocklisted" } },
      { do: "wait", ms: 1600 },
      { do: "keys" },
      { do: "type", text: "nice try" },
      { do: "send" },
    ],
  },
  {
    id: "split",
    tab: "Split a bill",
    name: "Trip group",
    typed: "236 for 4 of us",
    shows: "59 each · insert",
    steps: [
      { do: "them", text: "cab was 236, how much each?" },
      { do: "type", text: "236 for 4 of us" },
      { do: "strip", strip: { kind: "chip", title: "= 59 each", sub: "Worked out on the phone", action: "Insert" } },
      { do: "act" },
      { do: "set", text: "59 each 🚕" },
      { do: "strip", strip: words("each", "🚕", "done") },
      { do: "send" },
      { do: "them", text: "sending now" },
    ],
  },
  {
    id: "vault",
    tab: "Share your address",
    name: "Riya",
    typed: "vault",
    shows: "My NEAR · airkey-harshal.testnet",
    steps: [
      { do: "them", text: "what's your near address?" },
      {
        do: "panel",
        panel: {
          kind: "vault",
          items: [["My NEAR", "airkey-harshal.testnet"]],
        },
      },
      { do: "act" },
      { do: "keys" },
      { do: "set", text: "airkey-harshal.testnet" },
      { do: "send" },
      { do: "them", text: "sent ✓" },
    ],
  },
];
