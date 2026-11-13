// What the keyboard does in each demo chat. Every outcome here matches a run recorded in the README.

export type Tone = "paid" | "blocked" | "pending" | "info";

export type Bar =
  | { kind: "words"; words: string[] }
  | { kind: "intent"; icon: "pay" | "price" | "swap" | "calc" | "scan"; title: string; sub: string; action: string; hold: boolean }
  | { kind: "vault"; label: string; value: string }
  | { kind: "result"; tone: Tone; title: string; sub?: string; share?: boolean };

export type Step =
  | { do: "them"; text: string }
  | { do: "type"; text: string }
  | { do: "set"; text: string }
  | { do: "bar"; bar: Bar }
  | { do: "act" } // the visitor holds or taps the bar's button (or the demo does it for them)
  | { do: "send"; text?: string }
  | { do: "copied"; text: string }
  | { do: "wait"; ms: number };

export type Scenario = { id: string; tab: string; name: string; typed: string; shows: string; steps: Step[] };

const W = (...words: string[]): Bar => ({ kind: "words", words });

export const SCENARIOS: Scenario[] = [
  {
    id: "pay",
    tab: "Pay a friend",
    name: "Harshal",
    typed: "pay harshal 0.2 for dinner",
    shows: "Pay 0.2 NEAR to harshal · Hold to pay",
    steps: [
      { do: "them", text: "dinner was so good 🍜 you owe me 0.2" },
      { do: "type", text: "pay harshal 0.2 for dinner" },
      { do: "bar", bar: { kind: "intent", icon: "pay", title: "Pay 0.2 NEAR to harshal", sub: "Pay Agent · inside your caps", action: "Hold to pay", hold: true } },
      { do: "act" },
      { do: "bar", bar: { kind: "result", tone: "paid", title: "Paid 0.2 NEAR to harshal.near", sub: "The leash sent it · tx HRhR7pS9…", share: true } },
      { do: "wait", ms: 900 },
      { do: "send", text: "Paid 0.2 NEAR ✓ testnet.nearblocks.io/txns/HRhR7pS9…" },
      { do: "them", text: "got it, thanks 🙏" },
    ],
  },
  {
    id: "price",
    tab: "Price → buy",
    name: "Aman",
    typed: "$near",
    shows: "NEAR $3.39 · Buy",
    steps: [
      { do: "them", text: "is near moving today?" },
      { do: "type", text: "$near" },
      { do: "bar", bar: { kind: "intent", icon: "price", title: "NEAR $3.39", sub: "Live price from NEAR Intents", action: "Buy", hold: false } },
      { do: "act" },
      { do: "set", text: "buy $2 of near" },
      { do: "bar", bar: { kind: "intent", icon: "swap", title: "Buy $2 of NEAR", sub: "Trading Agent gets a quote first", action: "Hold to buy", hold: true } },
      { do: "act" },
      { do: "bar", bar: { kind: "result", tone: "paid", title: "2 USDC → 0.5861 NEAR", sub: "Quoted through NEAR Intents · inside the 1 NEAR cap" } },
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
      { do: "bar", bar: { kind: "intent", icon: "scan", title: "Check copied", sub: "Someone else's words go to the Inbox Agent", action: "Check", hold: false } },
      { do: "act" },
      { do: "bar", bar: { kind: "result", tone: "blocked", title: "Blocked by the leash (R4)", sub: "Over the 0.5 NEAR per-payment cap · drain.near reported" } },
      { do: "wait", ms: 1200 },
      { do: "type", text: "nice try" },
      { do: "send" },
    ],
  },
  {
    id: "split",
    tab: "Split a bill",
    name: "Trip group",
    typed: "236 for 4 of us",
    shows: "59 each · Insert",
    steps: [
      { do: "them", text: "cab was 236, how much each?" },
      { do: "type", text: "236 for 4 of us" },
      { do: "bar", bar: { kind: "intent", icon: "calc", title: "59 each", sub: "Worked out on the phone, no network", action: "Insert", hold: false } },
      { do: "act" },
      { do: "set", text: "59 each 🚕" },
      { do: "bar", bar: W("each", "🚕", "done") },
      { do: "send" },
      { do: "them", text: "sending now" },
    ],
  },
  {
    id: "vault",
    tab: "Share your address",
    name: "Riya",
    typed: "wallet key",
    shows: "My NEAR · airkey-harshal.testnet",
    steps: [
      { do: "them", text: "what's your near address? I'll send it back" },
      { do: "bar", bar: { kind: "vault", label: "My NEAR", value: "airkey-harshal.testnet" } },
      { do: "act" },
      { do: "set", text: "airkey-harshal.testnet" },
      { do: "bar", bar: W("thanks", "here", "👍") },
      { do: "send" },
      { do: "them", text: "sent ✓" },
    ],
  },
];
