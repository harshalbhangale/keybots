import { useCallback, useEffect, useRef, useState } from "react";
import { Ico } from "./Icons";

/**
 * The hero: a 3D Keybots keyboard. It types commands by itself; the visitor can
 * take over with their own keyboard, by tapping keys, or with the chips below.
 */

type Tone = "paid" | "blocked" | "pending" | "info";
type Result = { tone: Tone; title: string; meta: string };
type K = { k: string; label?: string; w?: number; sub?: string; cls?: string };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Letters with an action on a long press, as in the app. */
const SUB: Record<string, string> = { p: "PAY", s: "SWAP", c: "CHECK", f: "FOLLOW", k: "KILL" };

const ROWS: K[][] = [
  [{ k: "Escape", label: "", cls: "brand" }, ..."qwertyuiop".split("").map((c) => ({ k: c })), { k: "Backspace", label: "⌫", w: 1.5, cls: "fn" }],
  [{ k: "Tab", label: "tab", w: 1.35, cls: "fn" }, ..."asdfghjkl".split("").map((c) => ({ k: c })), { k: "Enter", label: "hold ↵", w: 1.9, cls: "go" }],
  [{ k: "Shift", label: "⇧", w: 1.85, cls: "fn" }, ..."zxcvbnm".split("").map((c) => ({ k: c })), { k: ".", label: "." }, { k: "$", label: "$" }, { k: "Shift2", label: "⇧", w: 1.4, cls: "fn" }],
  [{ k: "123", label: "123", w: 1.5, cls: "fn" }, { k: " ", label: "KEYBOTS", w: 7.4, cls: "space" }, { k: "0", label: "0" }, { k: "Near", label: "N", w: 1.5, cls: "fn near" }],
];
const ALL = new Set(ROWS.flat().map((x) => x.k));

/** What the keyboard does with a line. A page demo, worded like the app's results. */
function run(line: string): Result {
  const t = line.trim().toLowerCase();
  if (!t) return { tone: "info", title: "Type a command", meta: "try: pay harshal 0.2" };
  if (/drain|urgent|seed|private key/.test(t)) return { tone: "blocked", title: "Blocked by Spend Limits", meta: "a known scam account · checked on NEAR" };
  if (/^(kill|stop)/.test(t)) return { tone: "blocked", title: "Every agent stopped", meta: "one switch · the contract enforces it" };
  const pay = t.match(/^(?:pay|send)\s+([a-z0-9_.-]+)\s+([\d.]+)/) ?? t.match(/^(?:pay|send)\s+([\d.]+)\s+(?:near\s+)?to\s+([a-z0-9_.-]+)/);
  if (pay) {
    const [who, amt] = /^\d/.test(pay[1]) ? [pay[2], pay[1]] : [pay[1], pay[2]];
    const n = parseFloat(amt);
    const to = who.includes(".") ? who : `${who}.near`;
    if (n > 0.5) return { tone: "blocked", title: `${n} NEAR is over your limit`, meta: "0.5 NEAR a payment · Spend Limits said no" };
    if (/^new|designer/.test(who)) return { tone: "pending", title: `Waiting for your Face ID`, meta: `${to} is new · pending on chain` };
    return { tone: "paid", title: `Paid ${n} NEAR to ${to}`, meta: "hold to confirm · checked on NEAR" };
  }
  const swap = t.match(/^swap\s+([\d.]+)\s*(near|usdc)?/);
  if (swap) return { tone: "paid", title: `Swap ${swap[1]} ${(swap[2] ?? "near").toUpperCase()} on Rhea`, meta: "priced by NEAR Intents · inside your trade cap" };
  if (/^(\$|price)/.test(t)) return { tone: "info", title: "Live price card", meta: "from NEAR Intents, in the suggestion bar" };
  if (/^follow/.test(t)) return { tone: "paid", title: "Following, inside your caps", meta: "their next call trades for you" };
  if (/^(fix|rewrite)/.test(t)) return { tone: "info", title: "Rewritten privately", meta: "NEAR AI Cloud · attestation checked" };
  return { tone: "info", title: "Not a command, just typing", meta: "try: pay harshal 0.2 · swap 1 near · kill" };
}

const DEMO = ["pay harshal 0.2 for dinner", "send 5 near to drain.near", "swap 1 near to usdc", "pay designer 0.3"];
const CHIPS: { n: string; t: string }[] = [
  { n: "pay", t: "pay harshal 0.2" },
  { n: "x", t: "send 5 near to drain.near" },
  { n: "swap", t: "swap 1 near to usdc" },
  { n: "face", t: "pay designer 0.3" },
  { n: "stop", t: "kill" },
];

export default function Keyboard3D() {
  const [text, setText] = useState("");
  const [res, setRes] = useState<Result | null>(null);
  const [down, setDown] = useState<Set<string>>(new Set());
  const [pulse, setPulse] = useState(0);
  const wrap = useRef<HTMLDivElement>(null);
  const deck = useRef<HTMLDivElement>(null);
  const human = useRef(0); // last time the visitor touched it
  const job = useRef(0); // cancels a running auto-type
  const textRef = useRef("");
  const seen = useRef(true);

  const set = (s: string) => {
    textRef.current = s;
    setText(s);
  };
  const flash = useCallback((k: string, ms = 120) => {
    setDown((d) => new Set(d).add(k));
    setPulse((p) => p + 1);
    setTimeout(
      () =>
        setDown((d) => {
          const n = new Set(d);
          n.delete(k);
          return n;
        }),
      ms,
    );
  }, []);

  const keyFor = (ch: string) => (ch === " " ? " " : ALL.has(ch.toLowerCase()) ? ch.toLowerCase() : /\d/.test(ch) ? "0" : "");

  const enter = useCallback(() => {
    flash("Enter", 380);
    setRes(run(textRef.current));
  }, [flash]);

  const press = useCallback(
    (k: string) => {
      if (k === "Backspace") {
        flash(k);
        setRes(null);
        set(textRef.current.slice(0, -1));
      } else if (k === "Enter") enter();
      else if (k === "Escape") {
        flash(k);
        setRes(null);
        set("");
      } else if (k.length === 1) {
        flash(keyFor(k) || k);
        setRes(null);
        set((textRef.current + k).slice(0, 44));
      } else flash(k);
    },
    [enter, flash],
  );

  /** Types a line key by key, then runs it. */
  const typeOut = useCallback(
    async (line: string, mine: boolean) => {
      const id = ++job.current;
      const alive = () => job.current === id;
      setRes(null);
      for (let i = textRef.current.length; i > 0 && alive(); i--) {
        set(textRef.current.slice(0, -1));
        flash("Backspace", 60);
        await sleep(18);
      }
      for (const ch of line) {
        if (!alive()) return;
        set(textRef.current + ch);
        const k = keyFor(ch);
        if (k) flash(k, 90);
        await sleep(ch === " " ? 95 : 48 + Math.random() * 46);
      }
      await sleep(mine ? 260 : 520);
      if (alive()) enter();
    },
    [enter, flash],
  );

  // Auto-play while nobody is typing and the hero is on screen.
  useEffect(() => {
    let alive = true;
    const io = new IntersectionObserver(([e]) => (seen.current = e.isIntersecting));
    if (wrap.current) io.observe(wrap.current);
    (async () => {
      await sleep(1100);
      for (let i = 0; alive; i = (i + 1) % DEMO.length) {
        while (alive && (!seen.current || Date.now() - human.current < 7000)) await sleep(500);
        if (!alive) return;
        await typeOut(DEMO[i], false);
        await sleep(2600);
      }
    })();
    return () => {
      alive = false;
      job.current++;
      io.disconnect();
    };
  }, [typeOut]);

  // The visitor's own keyboard drives the 3D one while the hero is in view.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!seen.current || e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      const k = e.key;
      const typing = k.length === 1 || k === "Backspace" || k === "Enter" || k === "Escape";
      if (!typing) return;
      if (k === " " && !textRef.current) return; // let space scroll the page until they start typing
      e.preventDefault();
      human.current = Date.now();
      job.current++;
      press(k === "Enter" || k === "Backspace" || k === "Escape" || k === " " ? k : k);
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [press]);

  // A slow tilt that follows the pointer.
  useEffect(() => {
    const el = wrap.current;
    const d = deck.current;
    if (!el || !d || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let tx = 0,
      ty = 0,
      x = 0,
      y = 0,
      raf = 0;
    const move = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
      ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    };
    const leave = () => ((tx = 0), (ty = 0));
    const tick = () => {
      x += (tx - x) * 0.06;
      y += (ty - y) * 0.06;
      d.style.setProperty("--px", x.toFixed(3));
      d.style.setProperty("--py", y.toFixed(3));
      raf = requestAnimationFrame(tick);
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerleave", leave);
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerleave", leave);
    };
  }, []);

  const tap = (k: string) => {
    human.current = Date.now();
    job.current++;
    press(k === "Shift" || k === "Shift2" || k === "Tab" || k === "123" || k === "Near" ? k : k);
  };

  return (
    <div className="kb3" ref={wrap}>
      <div className={`kb3-screen ${res ? "done " + res.tone : ""}`} aria-live="polite">
        {res ? (
          <span className="kb3-res" key={res.title + pulse}>
            <span className="kb3-ico">
              <Ico n={res.tone === "blocked" ? "x" : res.tone === "pending" ? "face" : res.tone === "paid" ? "ok" : "spark"} s={16} />
            </span>
            <b>{res.title}</b>
            <small>{res.meta}</small>
          </span>
        ) : (
          <span className="kb3-text">
            {text || <span className="kb3-ph">Type on your keyboard…</span>}
            <span className="kb3-caret" />
          </span>
        )}
      </div>

      <div className="kb3-stage">
        <div className="kb3-deck" ref={deck} style={{ "--hit": pulse % 2 } as React.CSSProperties}>
          <div className="kb3-glow" key={pulse} aria-hidden />
          {ROWS.map((row, ri) => (
            <div className="kb3-row" key={ri}>
              {row.map((x) => (
                <button
                  key={x.k}
                  type="button"
                  tabIndex={-1}
                  aria-label={x.k === "Escape" ? "Clear" : x.label ?? x.k}
                  className={`k3 ${x.cls ?? ""} ${down.has(x.k) ? "down" : ""} ${SUB[x.k] ? "bound" : ""}`}
                  style={{ flexGrow: x.w ?? 1 }}
                  onPointerDown={(e) => {
                    e.preventDefault();
                    tap(x.k);
                  }}
                >
                  <span className="k3-cap">
                    {x.cls === "brand" ? <img src="/logo.svg" alt="" /> : <span className="k3-l">{x.label ?? x.k}</span>}
                    {SUB[x.k] && <em>{SUB[x.k]}</em>}
                  </span>
                </button>
              ))}
            </div>
          ))}
        </div>
        <div className="kb3-shadow" aria-hidden />
      </div>

      <div className="kb3-chips">
        {CHIPS.map((c) => (
          <button
            key={c.t}
            type="button"
            onClick={() => {
              human.current = Date.now();
              typeOut(c.t, true);
            }}
          >
            <Ico n={c.n} s={14} /> {c.t}
          </button>
        ))}
      </div>
    </div>
  );
}
