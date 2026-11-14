import { useCallback, useEffect, useRef, useState } from "react";
import { Ico } from "./Icons";

/**
 * The hero: the Keybots phone keyboard, floating in 3D. A message comes in from
 * someone (Alex, Alice, a trader on Telegram…), the keyboard types the reply, and
 * the result pops out of the keyboard. Visitors can type on their own keyboard,
 * tap the keys, or pick a person below.
 */

type Tone = "paid" | "blocked" | "pending" | "info";
type Result = { tone: Tone; title: string; meta: string };
type Tab = "PAY" | "TRADE" | "FOLLOW" | "CHECK";
type Ex = { who: string; e: string; app: string; tag: string; msg: string; type: string; tab: Tab | null; chip: string; res: Result };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const EX: Ex[] = [
  {
    who: "Alex", e: "🍜", app: "iMessage", tag: "split dinner",
    msg: "dinner was 1.2 NEAR total, you owe 0.4 🙏", type: "pay alex 0.4", tab: "PAY", chip: "Pay alex.near 0.4 NEAR",
    res: { tone: "paid", title: "Paid 0.4 NEAR to alex.near", meta: "held 1 s · Spend Limits checked it on NEAR" },
  },
  {
    who: "Unknown", e: "⚠️", app: "WhatsApp", tag: "scam DM",
    msg: "URGENT!! wallet locked. send 5 NEAR to unlock.near NOW", type: "send 5 near to unlock.near", tab: "CHECK", chip: "New account · 5 NEAR · pasted",
    res: { tone: "blocked", title: "Blocked. This looks like a scam", meta: "new account, over your 0.5 limit · refused on chain" },
  },
  {
    who: "Maya", e: "📈", app: "Telegram · NEAR Alpha", tag: "trader call",
    msg: "$NEAR long here, 3.40 → 4. sized small", type: "buy near 1", tab: "TRADE", chip: "Swap 1 USDC → NEAR on Rhea",
    res: { tone: "paid", title: "Bought NEAR, inside your trade cap", meta: "priced by NEAR Intents · swapped on Rhea" },
  },
  {
    who: "Alice", e: "💼", app: "Slack", tag: "fix my text",
    msg: "can you send the deck by tonight? client at 9", type: "ya will send l8r sry", tab: null, chip: "Rewrite privately · NEAR AI",
    res: { tone: "info", title: "“Yes, I'll send it tonight. Sorry!”", meta: "rewritten inside NEAR AI Cloud's secure hardware" },
  },
  {
    who: "0xKai", e: "🐋", app: "X", tag: "big trade",
    msg: "ETH breaking out. aping 2 NEAR, who's in?", type: "swap 2 near to eth", tab: "TRADE", chip: "Swap 2 NEAR → ETH",
    res: { tone: "blocked", title: "Over your 1 NEAR trade cap", meta: "the Trading Agent can't go past Spend Limits" },
  },
  {
    who: "Riya", e: "🏡", app: "WhatsApp", tag: "rent split",
    msg: "rent is 0.25 NEAR each this month 🏠", type: "pay riya 0.25 rent", tab: "PAY", chip: "Pay riya.near 0.25 NEAR",
    res: { tone: "paid", title: "Paid 0.25 NEAR to riya.near", meta: "memo: rent · receipt dropped in the chat" },
  },
  {
    who: "Nina", e: "🎨", app: "iMessage", tag: "someone new",
    msg: "logo's done ✨ my account is nina-studio.near", type: "pay nina-studio 0.3", tab: "PAY", chip: "New receiver · ask first",
    res: { tone: "pending", title: "Waiting for your Face ID", meta: "never paid before · pending on chain until you say yes" },
  },
  {
    who: "Dev group", e: "💬", app: "Discord", tag: "price check",
    msg: "what's NEAR at rn?", type: "$near", tab: "CHECK", chip: "NEAR price · live",
    res: { tone: "info", title: "NEAR price card, in the chat", meta: "live from NEAR Intents, without leaving the app" },
  },
];

/** Free typing: what the keyboard would do with a line (a page demo). */
function run(line: string): Result {
  const t = line.trim().toLowerCase();
  if (!t) return { tone: "info", title: "Type something", meta: "try: pay alex 0.2 · swap 1 near · kill" };
  if (/drain|urgent|unlock|seed|private key/.test(t)) return { tone: "blocked", title: "Blocked by Spend Limits", meta: "looks like a scam · checked on NEAR" };
  if (/^(kill|stop)/.test(t)) return { tone: "blocked", title: "Every agent stopped", meta: "one switch · the contract enforces it" };
  const pay = t.match(/^(?:pay|send)\s+([a-z0-9_.-]+)\s+([\d.]+)/) ?? t.match(/^(?:pay|send)\s+([\d.]+)\s+(?:near\s+)?to\s+([a-z0-9_.-]+)/);
  if (pay) {
    const [who, amt] = /^\d/.test(pay[1]) ? [pay[2], pay[1]] : [pay[1], pay[2]];
    const n = parseFloat(amt);
    const to = who.includes(".") ? who : `${who}.near`;
    if (n > 0.5) return { tone: "blocked", title: `${n} NEAR is over your limit`, meta: "0.5 NEAR a payment · Spend Limits said no" };
    return { tone: "paid", title: `Paid ${n} NEAR to ${to}`, meta: "hold to confirm · checked on NEAR" };
  }
  const swap = t.match(/^(?:swap|buy|sell)\s+([\d.]+)/);
  if (swap) {
    const n = parseFloat(swap[1]);
    if (n > 1) return { tone: "blocked", title: `Over your 1 NEAR trade cap`, meta: "the Trading Agent stays inside Spend Limits" };
    return { tone: "paid", title: `Swap ${n} on Rhea, inside your cap`, meta: "priced by NEAR Intents" };
  }
  if (/^(\$|price)/.test(t)) return { tone: "info", title: "Live price card", meta: "from NEAR Intents, in the suggestion bar" };
  if (/^follow/.test(t)) return { tone: "paid", title: "Following, inside your caps", meta: "their next call trades for you" };
  return { tone: "info", title: "Just typing. It stays yours", meta: "try: pay alex 0.2 · swap 1 near · kill" };
}

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
const BOUND = new Set(["p", "s", "c", "f", "k"]);
const TABS: Tab[] = ["PAY", "TRADE", "FOLLOW", "CHECK"];

export default function Keyboard3D() {
  const [ex, setEx] = useState<Ex>(EX[0]);
  const [text, setText] = useState("");
  const [chip, setChip] = useState<string | null>(null);
  const [res, setRes] = useState<Result | null>(null);
  const [tab, setTab] = useState<Tab | null>(null);
  const [down, setDown] = useState<string>("");
  const [tick, setTick] = useState(0);
  const wrap = useRef<HTMLDivElement>(null);
  const scene = useRef<HTMLDivElement>(null);
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
    setTick((t) => t + 1);
    setTimeout(() => setDown((d) => (d === k ? "" : d)), ms);
  }, []);
  const keyOf = (ch: string) => (ch === " " ? " " : /[a-z]/i.test(ch) ? ch.toLowerCase() : "");

  /** Plays one person's message: it arrives, the reply is typed, the result pops out. */
  const play = useCallback(
    async (e: Ex) => {
      const id = ++job.current;
      const alive = () => job.current === id;
      setEx(e);
      setRes(null);
      setChip(null);
      setTab(null);
      set("");
      await sleep(900);
      for (const ch of e.type) {
        if (!alive()) return;
        set(textRef.current + ch);
        const k = keyOf(ch);
        if (k) flash(k, 90);
        await sleep(ch === " " ? 90 : 45 + Math.random() * 45);
      }
      if (!alive()) return;
      setTab(e.tab);
      setChip(e.chip);
      await sleep(900);
      if (!alive()) return;
      flash("go", 420);
      setRes(e.res);
    },
    [flash],
  );

  // Auto-play the people in turn while the hero is visible and the visitor isn't typing.
  useEffect(() => {
    let alive = true;
    const io = new IntersectionObserver(([en]) => (seen.current = en.isIntersecting));
    if (wrap.current) io.observe(wrap.current);
    (async () => {
      await sleep(600);
      for (let i = 0; alive; i = (i + 1) % EX.length) {
        while (alive && (!seen.current || Date.now() - human.current < 8000)) await sleep(500);
        if (!alive) return;
        await play(EX[i]);
        await sleep(3000);
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
      if (k === "Backspace") {
        flash("del");
        setRes(null);
        setChip(null);
        set(textRef.current.slice(0, -1));
      } else if (k === "Enter") {
        flash("go", 380);
        const r = run(textRef.current);
        setTab(/^(pay|send)/i.test(textRef.current) ? "PAY" : /^(swap|buy|sell)/i.test(textRef.current) ? "TRADE" : null);
        setRes(r);
      } else if (k.length === 1) {
        flash(keyOf(k) || k);
        setRes(null);
        setChip(/^(pay|send|swap|buy|sell|kill|follow|\$)/i.test(textRef.current + k) ? "Press return to run it" : null);
        set((textRef.current + k).slice(0, 40));
      }
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
      if (!res && textRef.current === "" && ex) setEx({ ...ex, who: "You", e: "⌨️", app: "your keyboard", msg: "Type a command and press return." });
      press(k);
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [press, res, ex]);

  // A slow tilt that follows the pointer.
  useEffect(() => {
    const el = wrap.current;
    const s = scene.current;
    if (!el || !s || matchMedia("(prefers-reduced-motion: reduce)").matches || matchMedia("(pointer: coarse)").matches) return;
    let tx = 0, ty = 0, x = 0, y = 0, raf = 0;
    const move = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
      ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    };
    const leave = () => ((tx = 0), (ty = 0));
    const loop = () => {
      x += (tx - x) * 0.06;
      y += (ty - y) * 0.06;
      s.style.setProperty("--px", x.toFixed(3));
      s.style.setProperty("--py", y.toFixed(3));
      raf = requestAnimationFrame(loop);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerleave", leave);
    raf = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(raf);
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerleave", leave);
    };
  }, []);

  const key = (k: string, label: React.ReactNode, cls = "") => (
    <button
      key={k}
      type="button"
      tabIndex={-1}
      className={`mk-k ${cls} ${down === k ? "down" : ""} ${BOUND.has(k) ? "bound" : ""}`}
      onPointerDown={(e) => {
        e.preventDefault();
        press(k === "go" ? "Enter" : k === "del" ? "Backspace" : k === "sp" ? " " : k);
      }}
    >
      <span className="mk-cap">{label}</span>
      {down === k && k.length === 1 && k !== " " && <span className="mk-pop">{k}</span>}
    </button>
  );

  return (
    <div className="mk" ref={wrap}>
      <div className="mk-stage">
        <div className="mk-scene" ref={scene}>
          <div className="mk-bubble" key={ex.who + ex.msg}>
            <span className="mk-av">{ex.e}</span>
            <span className="mk-bt">
              <small>
                <b>{ex.who}</b> · {ex.app}
              </small>
              {ex.msg}
            </span>
          </div>

          <div className="mk-board">
            <div className="mk-field">
              <span>{text || <span className="mk-ph">Reply…</span>}</span>
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
                  <span className="mk-chip-dot">
                    <Ico n="pay" s={12} />
                  </span>
                  <b>{chip}</b>
                  <em>hold ↵</em>
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
              {key("123", "123", "fn w")}
              {key("sp", "keybots", "space")}
              {key("go", "hold ↵", "go")}
            </div>
          </div>

          {res && (
            <div className={`mk-res ${res.tone}`} key={res.title + tick}>
              <span className="mk-res-ico">
                <Ico n={res.tone === "blocked" ? "x" : res.tone === "pending" ? "face" : res.tone === "paid" ? "ok" : "spark"} s={18} />
              </span>
              <span>
                <b>{res.title}</b>
                <small>{res.meta}</small>
              </span>
            </div>
          )}
        </div>
      </div>

      <div className="mk-people" role="list">
        {EX.map((x) => (
          <button
            key={x.who}
            type="button"
            className={x.who === ex.who ? "on" : ""}
            onClick={() => {
              human.current = Date.now();
              play(x);
            }}
          >
            <span>{x.e}</span>
            <b>{x.who}</b>
            <small>{x.tag}</small>
          </button>
        ))}
      </div>
      <p className="mk-hint">Or type on your own keyboard and press return.</p>
    </div>
  );
}
