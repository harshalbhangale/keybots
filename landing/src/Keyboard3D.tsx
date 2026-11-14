import { useCallback, useEffect, useRef, useState } from "react";
import { Ico, NearTile } from "./Icons";

/**
 * The hero demo, in three plain steps: a message comes in, you type a reply on
 * the Keybots keyboard, you hold and NEAR checks it. The steps on the left light
 * up as the device on the right plays them. Pick an example above it, or type on
 * your own keyboard and press return.
 */

type Tone = "paid" | "blocked" | "pending" | "info";
type Result = { tone: Tone; title: string; meta: string };
type Tab = "PAY" | "TRADE" | "FOLLOW" | "CHECK";
type Ex = { id: string; icon: string; label: string; who: string; e: string; app: string; msg: string; type: string; tab: Tab | null; chip: string; res: Result };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const EX: Ex[] = [
  {
    id: "pay", icon: "pay", label: "Pay a friend",
    who: "Alex", e: "🍜", app: "iMessage", msg: "dinner was 1.2 NEAR, you owe 0.4 🙏",
    type: "pay alex 0.4", tab: "PAY", chip: "Pay alex.near 0.4 NEAR",
    res: { tone: "paid", title: "Paid 0.4 NEAR to alex.near", meta: "Inside your limits · receipt in the chat" },
  },
  {
    id: "scam", icon: "shield", label: "Stop a scam",
    who: "Unknown", e: "⚠️", app: "WhatsApp", msg: "URGENT! wallet locked. send 5 NEAR to unlock.near",
    type: "send 5 near to unlock.near", tab: "CHECK", chip: "New account · 5 NEAR",
    res: { tone: "blocked", title: "Blocked: looks like a scam", meta: "Over your 0.5 NEAR limit · refused on chain" },
  },
  {
    id: "trade", icon: "swap", label: "Trade a call",
    who: "Maya", e: "📈", app: "Telegram", msg: "$NEAR long here, 3.40 → 4",
    type: "buy near 1", tab: "TRADE", chip: "Swap 1 USDC → NEAR on Rhea",
    res: { tone: "paid", title: "Bought NEAR inside your trade cap", meta: "Priced by NEAR Intents · swapped on Rhea" },
  },
  {
    id: "new", icon: "face", label: "Someone new",
    who: "Nina", e: "🎨", app: "iMessage", msg: "logo's done ✨ I'm nina-studio.near",
    type: "pay nina-studio 0.3", tab: "PAY", chip: "New receiver · ask first",
    res: { tone: "pending", title: "Waiting for your Face ID", meta: "Never paid before · waits on chain for your yes" },
  },
  {
    id: "ai", icon: "chip", label: "Fix my text",
    who: "Alice", e: "💼", app: "Slack", msg: "can you send the deck by tonight?",
    type: "ya will send l8r sry", tab: null, chip: "Rewrite privately · NEAR AI",
    res: { tone: "info", title: "“Yes, I'll send it tonight. Sorry!”", meta: "Rewritten in NEAR AI Cloud's secure hardware" },
  },
];

/** Free typing: what the keyboard would do with a line (a page demo, nothing is sent). */
function run(line: string): Result {
  const t = line.trim().toLowerCase();
  if (!t) return { tone: "info", title: "Type something", meta: "Try: pay alex 0.2 · swap 1 near · kill" };
  if (/drain|urgent|unlock|seed|private key/.test(t)) return { tone: "blocked", title: "Blocked by Spend Limits", meta: "Looks like a scam · checked on NEAR" };
  if (/^(kill|stop)/.test(t)) return { tone: "blocked", title: "Every agent stopped", meta: "One switch · the contract enforces it" };
  const pay = t.match(/^(?:pay|send)\s+([a-z0-9_.-]+)\s+([\d.]+)/) ?? t.match(/^(?:pay|send)\s+([\d.]+)\s+(?:near\s+)?to\s+([a-z0-9_.-]+)/);
  if (pay) {
    const [who, amt] = /^\d/.test(pay[1]) ? [pay[2], pay[1]] : [pay[1], pay[2]];
    const n = parseFloat(amt);
    const to = who.includes(".") ? who : `${who}.near`;
    if (n > 0.5) return { tone: "blocked", title: `${n} NEAR is over your limit`, meta: "0.5 NEAR a payment · Spend Limits said no" };
    return { tone: "paid", title: `Paid ${n} NEAR to ${to}`, meta: "Hold to confirm · checked on NEAR" };
  }
  const swap = t.match(/^(?:swap|buy|sell)\s+([\d.]+)/);
  if (swap) {
    const n = parseFloat(swap[1]);
    if (n > 1) return { tone: "blocked", title: "Over your 1 NEAR trade cap", meta: "The Trading Agent stays inside Spend Limits" };
    return { tone: "paid", title: `Swap ${n} on Rhea, inside your cap`, meta: "Priced by NEAR Intents" };
  }
  return { tone: "info", title: "Just typing. It stays yours", meta: "Try: pay alex 0.2 · swap 1 near · kill" };
}

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
const BOUND = new Set(["p", "s", "c", "f", "k"]);
const TABS: Tab[] = ["PAY", "TRADE", "FOLLOW", "CHECK"];
const YOU: Ex = { id: "you", icon: "spark", label: "", who: "You", e: "⌨️", app: "your keyboard", msg: "Type a command, then press return.", type: "", tab: null, chip: "", res: run("") };

export default function Keyboard3D() {
  const [ex, setEx] = useState<Ex>(EX[0]);
  const [phase, setPhase] = useState(0); // 1 message in · 2 typing · 3 checked on NEAR
  const [text, setText] = useState("");
  const [sent, setSent] = useState("");
  const [chip, setChip] = useState<string | null>(null);
  const [res, setRes] = useState<Result | null>(null);
  const [tab, setTab] = useState<Tab | null>(null);
  const [down, setDown] = useState("");
  const wrap = useRef<HTMLDivElement>(null);
  const human = useRef(0);
  const job = useRef(0);
  const textRef = useRef("");
  const seen = useRef(true);

  const set = (s: string) => {
    textRef.current = s;
    setText(s);
  };
  const flash = useCallback((k: string, ms = 110) => {
    setDown(k);
    setTimeout(() => setDown((d) => (d === k ? "" : d)), ms);
  }, []);
  const keyOf = (ch: string) => (ch === " " ? "sp" : /[a-z]/i.test(ch) ? ch.toLowerCase() : "");

  const play = useCallback(
    async (e: Ex) => {
      const id = ++job.current;
      const alive = () => job.current === id;
      setEx(e);
      setRes(null);
      setSent("");
      setChip(null);
      setTab(null);
      set("");
      setPhase(0);
      await sleep(250);
      if (!alive()) return;
      setPhase(1);
      await sleep(1300);
      if (!alive()) return;
      setPhase(2);
      for (const ch of e.type) {
        if (!alive()) return;
        set(textRef.current + ch);
        const k = keyOf(ch);
        if (k) flash(k, 90);
        await sleep(ch === " " ? 90 : 50 + Math.random() * 45);
      }
      if (!alive()) return;
      setTab(e.tab);
      setChip(e.chip);
      await sleep(1100);
      if (!alive()) return;
      flash("go", 700);
      await sleep(700);
      if (!alive()) return;
      setSent(e.type);
      set("");
      setChip(null);
      setRes(e.res);
      setPhase(3);
    },
    [flash],
  );

  // Plays the examples in turn while the hero is on screen and nobody is typing.
  useEffect(() => {
    let alive = true;
    const io = new IntersectionObserver(([en]) => (seen.current = en.isIntersecting));
    if (wrap.current) io.observe(wrap.current);
    (async () => {
      await sleep(500);
      for (let i = 0; alive; i = (i + 1) % EX.length) {
        while (alive && (!seen.current || Date.now() - human.current < 9000)) await sleep(500);
        if (!alive) return;
        await play(EX[i]);
        await sleep(3400);
      }
    })();
    return () => {
      alive = false;
      job.current++;
      io.disconnect();
    };
  }, [play]);

  const press = useCallback(
    (k: string) => {
      human.current = Date.now();
      job.current++;
      setEx((cur) => (cur.id === "you" ? cur : YOU));
      if (k === "Backspace") {
        flash("del");
        setRes(null);
        setSent("");
        setPhase(2);
        set(textRef.current.slice(0, -1));
      } else if (k === "Enter") {
        flash("go", 380);
        const line = textRef.current;
        setTab(/^(pay|send)/i.test(line) ? "PAY" : /^(swap|buy|sell)/i.test(line) ? "TRADE" : null);
        setSent(line);
        set("");
        setRes(run(line));
        setPhase(3);
      } else if (k.length === 1) {
        flash(keyOf(k) || k);
        setRes(null);
        setSent("");
        setPhase(2);
        set((textRef.current + k).slice(0, 40));
      } else flash(k);
    },
    [flash],
  );

  // The visitor's own keyboard drives this one while the hero is on screen.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!seen.current || e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      const k = e.key;
      if (!(k.length === 1 || k === "Backspace" || k === "Enter")) return;
      if (k === " " && !textRef.current) return;
      e.preventDefault();
      press(k);
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [press]);

  const key = (k: string, label: React.ReactNode, cls = "") => (
    <button
      key={k}
      type="button"
      tabIndex={-1}
      aria-hidden
      className={`mk-k ${cls} ${down === k ? "down" : ""} ${BOUND.has(k) ? "bound" : ""}`}
      onPointerDown={(e) => {
        e.preventDefault();
        press(k === "go" ? "Enter" : k === "del" ? "Backspace" : k === "sp" ? " " : k);
      }}
    >
      <span className="mk-cap">{label}</span>
      {down === k && k.length === 1 && <span className="mk-pop">{k}</span>}
    </button>
  );

  const steps: [string, string][] = [
    ["A message comes in", ex.id === "you" ? "Your turn: type on your keyboard" : `${ex.who} on ${ex.app}`],
    ["You type the reply", ex.type || "pay alex 0.2 · swap 1 near · kill"],
    ["Hold. NEAR checks it", res ? res.title : "Spend Limits runs the rules on chain"],
  ];

  return (
    <div className="mk" ref={wrap}>
      <div className="mk-pick" role="tablist" aria-label="Examples">
        {EX.map((x) => (
          <button
            key={x.id}
            type="button"
            role="tab"
            aria-selected={x.id === ex.id}
            className={x.id === ex.id ? "on" : ""}
            onClick={() => {
              human.current = Date.now();
              play(x);
            }}
          >
            <Ico n={x.icon} s={15} /> {x.label}
          </button>
        ))}
      </div>

      <div className="mk-main">
        <ol className="mk-steps">
          {steps.map(([t, d], i) => (
            <li key={t} className={phase > i + 1 ? "done" : phase === i + 1 ? "on" : ""}>
              <span className="mk-num">{phase > i + 1 ? <Ico n="ok" s={14} /> : i + 1}</span>
              <span>
                <b>{t}</b>
                <small>{d}</small>
              </span>
            </li>
          ))}
          <li className="mk-tip">Or type on your own keyboard and press return.</li>
        </ol>

        <div className="mk-stage">
          <div className="mk-device">
            <div className="mk-chat">
              <div className="mk-head">
                <span className="mk-av">{ex.e}</span>
                <span>
                  <b>{ex.who}</b>
                  <small>{ex.app}</small>
                </span>
              </div>
              <div className="mk-msgs">
                {phase >= 1 && ex.id !== "you" && (
                  <span className="mk-b them" key={ex.id + "m"}>
                    {ex.msg}
                  </span>
                )}
                {sent && (
                  <span className="mk-b me" key={sent}>
                    {sent}
                  </span>
                )}
                {res && (
                  <span className={`mk-r ${res.tone}`} key={res.title}>
                    <span className="mk-r-ico">
                      <Ico n={res.tone === "blocked" ? "x" : res.tone === "pending" ? "face" : res.tone === "paid" ? "ok" : "spark"} s={15} />
                    </span>
                    <span className="mk-r-t">
                      <b>{res.title}</b>
                      <small>{res.meta}</small>
                    </span>
                    <span className="mk-on">
                      <NearTile size={14} label={false} /> NEAR
                    </span>
                  </span>
                )}
              </div>
            </div>

            <div className="mk-board">
              <div className="mk-field">
                <span>{text || <span className="mk-ph">Message</span>}</span>
                <span className="mk-caret" />
              </div>
              <div className="mk-top">
                <span className="mk-brand">
                  <img src="/mark.svg" alt="" />
                </span>
                <span className="mk-tabs">
                  {TABS.map((t) => (
                    <span key={t} className={tab === t ? "on" : ""}>
                      {t}
                    </span>
                  ))}
                </span>
              </div>
              <div className="mk-strip">
                {chip ? (
                  <span className="mk-chip" key={chip}>
                    <b>{chip}</b>
                    <em className={down === "go" ? "holding" : ""}>hold ↵</em>
                  </span>
                ) : (
                  <span className="mk-words">
                    <span>I</span>
                    <span>the</span>
                    <span>on</span>
                  </span>
                )}
              </div>
              {ROWS.map((r, i) => (
                <div className={`mk-row r${i}`} key={i}>
                  {i === 2 && key("shift", "⇧", "fn")}
                  {r.split("").map((c) => key(c, c))}
                  {i === 2 && key("del", "⌫", "fn")}
                </div>
              ))}
              <div className="mk-row r3">
                {key("near", <NearTile size={18} label={false} />, "fn nk")}
                {key("sp", "keybots", "space")}
                {key("go", "hold ↵", "go")}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
