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
  | { kind: "ai"; before: string; after: string; proof: [string, string][]; button: string }
  | { kind: "agents"; agents: [string, string, string][]; button: string }
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
  /** Which chat app the phone draws. iMessage when unset. */
  app?: "telegram" | "x";
  steps: Step[];
};

export type ChainLine = [string, "ok" | "fail" | "info"];

/** What happens on NEAR for each chat, shown next to the phone. */
export const CHAIN: Record<string, ChainLine[]> = {
  ai: [
    ["your words → NEAR AI Cloud, inside secure hardware (TEE)", "info"],
    ["the enclave signs its answer", "ok"],
    ["signature checked against the request and reply hashes", "ok"],
    ["hardware attestation checked", "ok"],
    ["you pick: use it or don't. Nothing is sent for you", "info"],
  ],
  agents: [
    ["pay · inbox · trader: one NEAR account each", "info"],
    ["each key can only call Spend Limits, nothing else", "ok"],
    ["own caps: 0.5 a payment · 1 NEAR a trade", "ok"],
    ["pasted text goes to the inbox agent, never trusted", "ok"],
    ["hold: kill switch on, signed by your owner key", "info"],
    ["next payment blocked by R1 · tx Hmk7LcjQ…", "fail"],
  ],
  pay: [
    ["pay.airkey-harshal.testnet → leash.pay(harshal.near, 0.2)", "info"],
    ["R1 kill switch off", "ok"],
    ["R3 harshal.near not blocklisted", "ok"],
    ["R4 0.2 ≤ 0.5 per payment", "ok"],
    ["R5 0.2 of 1.0 today", "ok"],
    ["Spend Limits sends 0.2 NEAR → harshal.near", "ok"],
    ["event paid · tx HRhR7pS9…", "info"],
  ],
  scam: [
    ["pasted → inbox.airkey-harshal.testnet (untrusted)", "info"],
    ["leash.pay(drain.near, 5)", "info"],
    ["R1 kill switch off", "ok"],
    ["R3 drain.near not blocklisted yet", "ok"],
    ["R4 5 > 0.5 per payment · blocked", "fail"],
    ["report(drain.near) → blocklist", "info"],
    ["event blocked · tx HMeo4MYz…", "info"],
  ],
  approve: [
    ["pay.airkey-harshal.testnet → leash.pay(designer.near, 0.3)", "info"],
    ["server check: new account, never paid → ask_owner", "info"],
    ["R1 to R6 pass", "ok"],
    ["R7 the agent asked you · pending on chain", "info"],
    ["tx 4Zckku5j…", "info"],
    ["you approve in the app: Face ID, the phone signs", "ok"],
    ["Spend Limits re-checks R1 and R3, then pays", "ok"],
  ],
  swap: [
    ["trader.airkey-harshal.testnet → leash.swap(0.1 NEAR → USDC)", "info"],
    ["R1 kill switch off", "ok"],
    ["Trading Agent cap: 0.1 of 1 NEAR a trade", "ok"],
    ["Spend Limits wraps 0.1 NEAR and swaps on Rhea", "info"],
    ["0.2101 USDC comes back to Spend Limits", "ok"],
    ["tx 89dXiQh4…", "info"],
  ],
  call: [
    ["copied text read as a call: NEAR long, target $4", "info"],
    ["token checked against NEAR Intents' list", "ok"],
    ["Trading Agent cap: 0.1 of 1 NEAR a trade", "ok"],
    ["hold: leash.swap runs on Rhea (testnet)", "info"],
    ["tx 7XUq6MLF…", "info"],
  ],
  order: [
    ["order: sell 1 NEAR when price < $2", "info"],
    ["price now $3.39 from NEAR Intents", "ok"],
    ["watcher checks every 15 s", "info"],
    ["pasted text can never set an order", "ok"],
  ],
  split: [
    ["236 ÷ 4 = 59", "ok"],
    ["worked out on the phone", "info"],
    ["nothing sent to NEAR", "info"],
  ],
  vault: [
    ["vault holds addresses only", "ok"],
    ["refuses keys and recovery phrases", "ok"],
    ["inserted airkey-harshal.testnet", "info"],
  ],
  follow: [
    ["follow @nearwhale: 1 NEAR a call, 3 a day, buy only", "info"],
    ["a new call passes your rules", "ok"],
    ["Trading Agent swaps inside its Spend Limits caps", "ok"],
    ["live on testnet · tx 5MyPgFPD…", "info"],
  ],
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
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Paid 0.2 NEAR", sub: "to harshal.near · Spend Limits sent it", tx: "HRhR7pS9…" } },
      { do: "wait", ms: 1300 },
      { do: "keys" },
      { do: "send", text: "Paid 0.2 NEAR ✓ nearblocks.io/txns/HRhR7pS9…" },
      { do: "them", text: "got it, thanks 🙏" },
    ],
  },
  {
    id: "scam",
    who: "Unknown",
    emoji: "⚠️",
    tag: "Scam check",
    preview: "URGENT! Your account is locked…",
    headline: ["A scam in your DMs?", "NEAR says no."],
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
      { do: "panel", panel: { kind: "done", tone: "blocked", title: "Blocked by Spend Limits", sub: "R4 · drain.near reported and blocklisted" } },
      { do: "wait", ms: 1600 },
      { do: "keys" },
      { do: "type", text: "nice try" },
      { do: "send" },
    ],
  },
  {
    id: "approve",
    who: "Designer",
    emoji: "🎨",
    tag: "Approve",
    preview: "logo's done! designer.near",
    headline: ["Someone new?", "You approve with Face ID."],
    steps: [
      { do: "them", text: "logo's done ✨ my account is designer.near" },
      { do: "type", text: "pay designer 0.3 for the logo" },
      { do: "strip", strip: { kind: "chip", title: "Pay 0.3 NEAR to designer", sub: "for the logo", action: "Review" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "pay",
          amount: "0.3",
          to: "designer.near",
          memo: "for the logo",
          agent: "Pay Agent · trusted",
          checks: [
            ["Per payment", "0.3 of 0.5"],
            ["Today", "0.3 of 1.0"],
            ["Receiver", "new"],
          ],
          button: "Hold to pay",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "pending", title: "Waiting for you", sub: "New receiver (R7). Approve in Keybots with Face ID.", tx: "4Zckku5j…" } },
      { do: "wait", ms: 1800 },
      { do: "keys" },
    ],
  },
  {
    id: "swap",
    who: "Aman",
    emoji: "📈",
    tag: "Swap",
    preview: "swap some near to usdc?",
    headline: ["Swap in the chat.", "It runs on NEAR."],
    steps: [
      { do: "them", text: "move some near to usdc before the weekend?" },
      { do: "type", text: "swap 0.1 near to usdc" },
      {
        do: "panel",
        panel: {
          kind: "trade",
          badge: "SWAP",
          agent: "Trading Agent · on Rhea",
          pay: ["0.1", "NEAR", ""],
          get: ["≈ 0.2101", "USDC", ""],
          tiles: [
            ["Per trade", "0.1 of 1"],
            ["Route", "Rhea pool"],
            ["Lands in", "Spend Limits"],
          ],
          button: "Hold to swap",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Swapped 0.2101 USDC", sub: "back into Spend Limits, on testnet", tx: "89dXiQh4…" } },
      { do: "wait", ms: 1300 },
      { do: "keys" },
    ],
  },
  {
    id: "call",
    who: "NEAR Alpha",
    emoji: "📣",
    tag: "Copy a call",
    preview: "NEAR long here, target $4",
    headline: ["A call on Telegram?", "Copy it. Trade it."],
    app: "telegram",
    steps: [
      { do: "them", text: "Maya: NEAR long here, 3.40 → target $4 🚀" },
      { do: "copied", text: "NEAR long here, target $4" },
      { do: "strip", strip: { kind: "chip", title: "Trade NEAR?", sub: "A call: token checked on NEAR Intents", action: "Review" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "trade",
          badge: "CALL",
          agent: "Trading Agent · quote first",
          pay: ["0.1", "NEAR", ""],
          get: ["≈ 0.2101", "USDC", ""],
          tiles: [
            ["Token", "checked"],
            ["Per trade", "0.1 of 1"],
            ["Testnet", "Rhea"],
          ],
          button: "Hold to trade",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "paid", title: "Traded 0.1 NEAR", sub: "Rhea on testnet, inside the caps", tx: "7XUq6MLF…" } },
      { do: "wait", ms: 1300 },
      { do: "keys" },
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
    who: "NEAR Whale",
    emoji: "🐋",
    tag: "Follow a caller",
    preview: "@nearwhale: $NEAR long, target $4",
    headline: ["Follow a trader on X.", "Their calls trade for you."],
    app: "x",
    steps: [
      { do: "them", text: "$NEAR long here, 3.40 → target $4 🚀 not advice" },
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
  {
    id: "ai",
    who: "Alice (work)",
    emoji: "💼",
    tag: "Private AI",
    preview: "can you send the deck tonight?",
    headline: ["Private AI.", "Runs on NEAR, sees nothing."],
    steps: [
      { do: "them", text: "hey, can you send the deck by tonight? client call at 9" },
      { do: "type", text: "ya will send l8r sry swamped" },
      { do: "strip", strip: { kind: "chip", title: "Rewrite, privately", sub: "NEAR AI Cloud · secure hardware", action: "Fix" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "ai",
          before: "ya will send l8r sry swamped",
          after: "Yes, I'll send it tonight. Sorry, swamped today!",
          proof: [
            ["Runs in", "TEE"],
            ["Signature", "checked"],
            ["Attestation", "checked"],
          ],
          button: "Use it",
        },
      },
      { do: "act" },
      { do: "keys" },
      { do: "set", text: "Yes, I'll send it tonight. Sorry, swamped today!" },
      { do: "send" },
      { do: "them", text: "perfect, thanks 🙌" },
    ],
  },
  {
    id: "agents",
    who: "Keybots",
    emoji: "🤖",
    tag: "Agents",
    preview: "your agents",
    headline: ["Three agents.", "One kill switch."],
    steps: [
      { do: "them", text: "Trading Agent: swapped 0.1 NEAR → USDC for you ✓" },
      { do: "type", text: "agents" },
      { do: "strip", strip: { kind: "chip", title: "3 agents on NEAR", sub: "All inside Spend Limits", action: "Open" } },
      { do: "act" },
      {
        do: "panel",
        panel: {
          kind: "agents",
          agents: [
            ["Pay Agent", "0.5 a payment · 1 a day", "on"],
            ["Inbox Agent", "pasted text · asks first", "on"],
            ["Trading Agent", "1 NEAR a trade", "on"],
          ],
          button: "Hold to stop all",
        },
      },
      { do: "act" },
      { do: "panel", panel: { kind: "done", tone: "blocked", title: "Every agent stopped", sub: "Kill switch on, on chain. The next payment was refused.", tx: "Hmk7LcjQ…" } },
      { do: "wait", ms: 1400 },
      { do: "keys" },
    ],
  },
];
