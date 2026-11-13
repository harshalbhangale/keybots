// The demo chats. "live" ones match runs recorded in the top-level README; "soon" ones are next.

export type Tab = "PAY" | "TRADE" | "FOLLOW" | "CHECK";
export type Tone = "paid" | "blocked" | "pending";

/** The strip above the keys while you type. */
export type Strip =
  | { kind: "words"; words: string[] }
  | { kind: "chip"; title: string; sub: string; action: string };

/** What replaces the keys once an action is ready. */
export type Panel =
  | { kind: "pay"; amount: string; to: string; memo?: string; agent: string; checks: [string, string][]; button: string }
  | { kind: "trade"; badge: string; agent: string; pay: [string, string, string]; get: [string, string, string]; tiles: [string, string][]; button: string }
  | { kind: "check"; copied: string; trace: [string, string, "pass" | "fire"][]; agent: string }
  | { kind: "caller"; handle: string; name: string; hits: number; calls: number; last: string; tiles: [string, string][]; button: string }
  | { kind: "vault"; items: [string, string][] }
  | { kind: "done"; tone: Tone; title: string; sub: string; tx?: string };

export type Step =
  | { do: "them"; text: string }
  | { do: "type"; text: string }
  | { do: "set"; text: string }
  | { do: "strip"; strip: Strip }
  | { do: "panel"; panel: Panel }
  | { do: "keys" }
  | { do: "act" }
  | { do: "send"; text?: string }
  | { do: "copied"; text: string }
  | { do: "wait"; ms: number };

export type Scenario = {
  id: string;
  who: string;
  emoji: string;
  tag: string;
  preview: string;
  headline: [string, string];
  soon?: boolean;
  steps: Step[];
};

const words = (...w: string[]): Strip => ({ kind: "words", words: w });

export const SCENARIOS: Scenario[] = [
  {
    id: "pay",
    who: "Harshal",
    emoji: "🍜",
    tag: "Pay",
    preview: "dinner was so good, you owe me 0.2",
    headline: ["Owe a friend?", "Pay, mid-chat."],
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
      { do: "wait", ms: 1300 },
      { do: "keys" },
      { do: "send", text: "Paid 0.2 NEAR ✓ nearblocks.io/txns/HRhR7pS9…" },
      { do: "them", text: "got it, thanks 🙏" },
    ],
  },
  {
    id: "trade",
    who: "Aman",
    emoji: "📈",
    tag: "Price + buy",
    preview: "is near moving today?",
    headline: ["Price check?", "Buy it from the bar."],
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
          badge: "BUY",
          agent: "Trading Agent · quote first",
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
      { do: "wait", ms: 1300 },
      { do: "keys" },
    ],
  },
  {
    id: "scam",
    who: "Unknown",
    emoji: "⚠️",
    tag: "Scam check",
    preview: "URGENT! Your account is locked…",
    headline: ["A scam in your DMs?", "The leash says no."],
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
          agent: "Inbox Agent · untrusted",
          trace: [
            ["R1", "Kill switch off", "pass"],
            ["R3", "drain.near not blocklisted", "pass"],
            ["R4", "5 NEAR over the 0.5 cap", "fire"],
          ],
        },
      },
      { do: "wait", ms: 1700 },
      { do: "panel", panel: { kind: "done", tone: "blocked", title: "Blocked by the leash", sub: "R4 · drain.near reported and blocklisted" } },
      { do: "wait", ms: 1600 },
      { do: "keys" },
      { do: "type", text: "nice try" },
      { do: "send" },
    ],
  },
  {
    id: "order",
    who: "Trading desk",
    emoji: "🎯",
    tag: "Limit order",
    preview: "near looks weak today",
    headline: ["Set it and go.", "Orders from the keyboard."],
    steps: [
      { do: "them", text: "near looks weak today 📉" },
      { do: "type", text: "sell 1 near if it drops below 2" },
      {
        do: "panel",
        panel: {
          kind: "trade",
          badge: "ORDER",
          agent: "Trading Agent · watched every 15 s",
          pay: ["1", "NEAR", "now $3.39"],
          get: ["USDC", "", "if below $2"],
          tiles: [
            ["Trigger", "< $2.00"],
            ["Agent cap", "1 NEAR"],
            ["Route", "NEAR Intents"],
          ],
          button: "Hold to place",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "pending", title: "Watching NEAR", sub: "Sells 1 NEAR when the price crosses $2" } },
      { do: "wait", ms: 1300 },
      { do: "keys" },
    ],
  },
  {
    id: "split",
    who: "Trip group",
    emoji: "🚕",
    tag: "Math",
    preview: "cab was 236, how much each?",
    headline: ["Splitting a bill?", "Sums, on the phone."],
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
    who: "Riya",
    emoji: "🎁",
    tag: "Vault",
    preview: "what's your near address?",
    headline: ["Need your address?", "One tap from the vault."],
    steps: [
      { do: "them", text: "what's your near address?" },
      { do: "panel", panel: { kind: "vault", items: [["My NEAR", "airkey-harshal.testnet"]] } },
      { do: "act" },
      { do: "keys" },
      { do: "set", text: "airkey-harshal.testnet" },
      { do: "send" },
      { do: "them", text: "sent ✓" },
    ],
  },
  {
    id: "follow",
    who: "Alpha chat",
    emoji: "🐋",
    tag: "Follow a caller",
    preview: "@nearwhale: $NEAR long, target $4",
    headline: ["A call in the group?", "Check the caller first."],
    soon: true,
    steps: [
      { do: "them", text: "@nearwhale: $NEAR long here, target $4 🚀" },
      { do: "copied", text: "@nearwhale: $NEAR long, target $4" },
      { do: "strip", strip: { kind: "chip", title: "@nearwhale · 14 of 20 hit", sub: "Calls scored on chain", action: "Open" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "caller",
          handle: "@nearwhale",
          name: "NEAR Whale",
          hits: 14,
          calls: 20,
          last: "$NEAR long · target $4",
          tiles: [
            ["Per trade", "1 NEAR"],
            ["Per day", "3 NEAR"],
            ["Pasted", "never trades"],
          ],
          button: "Hold to follow",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Following @nearwhale", sub: "Copies their calls, inside your caps" } },
      { do: "wait", ms: 1300 },
      { do: "keys" },
    ],
  },
];
