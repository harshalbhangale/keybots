import { useCallback, useEffect, useRef, useState } from "react";
import { SCENARIOS, type Bar, type Scenario } from "./scenarios";

type Msg = { id: number; me: boolean; text: string };

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const HOLD_MS = 900;

function Icon({ name }: { name: string }) {
  const p = { width: 16, height: 16, viewBox: "0 0 16 16", fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  if (name === "pay") return <svg {...p}><path d="M4 12 12 4M6 4h6v6" /></svg>;
  if (name === "price") return <svg {...p}><path d="M2 12l4-4 3 3 5-6" /></svg>;
  if (name === "swap") return <svg {...p}><path d="M3 5h10l-3-3M13 11H3l3 3" /></svg>;
  if (name === "calc") return <svg {...p}><path d="M3 6h10M3 10h10" /></svg>;
  if (name === "scan") return <svg {...p}><path d="M5 2H3v3M11 2h2v3M5 14H3v-3M11 14h2v-3M5 8h6" /></svg>;
  if (name === "ok") return <svg {...p}><path d="M3 8.5 6.5 12 13 4.5" /></svg>;
  if (name === "x") return <svg {...p}><path d="M4 4l8 8M12 4l-8 8" /></svg>;
  if (name === "wallet") return <svg {...p}><rect x="2" y="4" width="12" height="9" rx="2" /><path d="M10.5 8.5h1" /></svg>;
  return null;
}

function BarView({ bar, holding, onAct, onHoldStart, onHoldEnd, hint }: { bar: Bar; holding: number; onAct: () => void; onHoldStart: () => void; onHoldEnd: () => void; hint: boolean }) {
  if (bar.kind === "words")
    return (
      <div className="kb-bar words">
        {bar.words.map((w, i) => (
          <span key={i} className={i === 1 ? "mid" : ""}>
            {w}
          </span>
        ))}
      </div>
    );
  if (bar.kind === "vault")
    return (
      <div className="kb-bar">
        <button className={`vault-chip ${hint ? "hint" : ""}`} onClick={onAct}>
          <b>{bar.label}</b> <code>{bar.value}</code>
        </button>
      </div>
    );
  if (bar.kind === "result")
    return (
      <div className={`kb-bar result ${bar.tone}`} key={bar.title}>
        <span className="ico">
          <Icon name={bar.tone === "blocked" ? "x" : "ok"} />
        </span>
        <span className="txt">
          <b>{bar.title}</b>
          {bar.sub && <small>{bar.sub}</small>}
        </span>
        {bar.share && <span className="share">Share</span>}
      </div>
    );
  return (
    <div className="kb-bar intent" key={bar.title}>
      <span className="ico lime">
        <Icon name={bar.icon} />
      </span>
      <span className="txt">
        <b>{bar.title}</b>
        <small>{bar.sub}</small>
      </span>
      {bar.hold ? (
        <button
          className={`act hold ${hint ? "hint" : ""}`}
          onPointerDown={onHoldStart}
          onPointerUp={onHoldEnd}
          onPointerLeave={onHoldEnd}
          onContextMenu={(e) => e.preventDefault()}
        >
          <span className="fill" style={{ width: `${holding * 100}%` }} />
          <span className="lbl">{bar.action}</span>
        </button>
      ) : (
        <button className={`act ${hint ? "hint" : ""}`} onClick={onAct}>
          {bar.action}
        </button>
      )}
    </div>
  );
}

function Keys({ lit, numbers, onWallet }: { lit: string; numbers: boolean; onWallet?: () => void }) {
  const rows = numbers ? ["1234567890", "-/:;()$&@\"", ".,?!'"] : ROWS;
  return (
    <div className="kb-keys" aria-hidden>
      {rows.map((r, ri) => (
        <div className={`kb-row r${ri}`} key={ri}>
          {ri === 2 && <span className="k mod">{numbers ? "#+=" : "⇧"}</span>}
          {r.split("").map((c) => (
            <span key={c} className={`k ${lit === c ? "lit" : ""} ${c === "p" ? "tab" : ""}`}>
              {c}
            </span>
          ))}
          {ri === 2 && <span className="k mod">⌫</span>}
        </div>
      ))}
      <div className="kb-row r3">
        <span className="k mod wide">{numbers ? "ABC" : "123"}</span>
        <span className="k mod wallet" onClick={onWallet}>
          <Icon name="wallet" />
        </span>
        <span className={`k space ${lit === " " ? "lit" : ""}`}>AIRKEY</span>
        <span className="k mod wide">return</span>
      </div>
    </div>
  );
}

/** A chat with the AIRKEY keyboard. It plays a scenario; the visitor can hold or tap the bar's button. */
export default function Phone({ scenario, onDone }: { scenario: Scenario; onDone?: () => void }) {
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [field, setField] = useState("");
  const [bar, setBar] = useState<Bar>({ kind: "words", words: ["I", "the", "on"] });
  const [lit, setLit] = useState("");
  const [holding, setHolding] = useState(0);
  const [waiting, setWaiting] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const actResolve = useRef<(() => void) | null>(null);
  const holdRaf = useRef(0);
  const holdStart = useRef(0);
  const run = useRef(0);
  const chat = useRef<HTMLDivElement>(null);
  const nextId = useRef(1);

  const act = useCallback(() => {
    if (!actResolve.current) return;
    const r = actResolve.current;
    actResolve.current = null;
    setWaiting(false);
    r();
  }, []);

  const holdTo = useCallback(
    (done: () => void) => {
      cancelAnimationFrame(holdRaf.current);
      holdStart.current = performance.now();
      const tick = () => {
        const k = Math.min(1, (performance.now() - holdStart.current) / HOLD_MS);
        setHolding(k);
        if (k >= 1) {
          done();
          setTimeout(() => setHolding(0), 200);
        } else holdRaf.current = requestAnimationFrame(tick);
      };
      holdRaf.current = requestAnimationFrame(tick);
    },
    [],
  );

  const onHoldStart = () => {
    if (actResolve.current) holdTo(act);
  };
  const onHoldEnd = () => {
    if (holding < 1) {
      cancelAnimationFrame(holdRaf.current);
      setHolding(0);
    }
  };

  useEffect(() => {
    const id = ++run.current;
    const alive = () => run.current === id;
    setMsgs([]);
    setField("");
    setCopied(null);
    setBar({ kind: "words", words: ["I", "the", "on"] });
    let text = "";
    let lastBar: Bar | null = null;

    (async () => {
      await sleep(500);
      for (const s of scenario.steps) {
        if (!alive()) return;
        if (s.do === "them") {
          await sleep(350);
          setMsgs((m) => [...m, { id: nextId.current++, me: false, text: s.text }]);
          await sleep(900);
        } else if (s.do === "type") {
          for (const ch of s.text) {
            if (!alive()) return;
            text += ch;
            setField(text);
            setLit(ch.toLowerCase());
            await sleep(ch === " " ? 110 : 55 + Math.random() * 60);
          }
          setLit("");
          await sleep(300);
        } else if (s.do === "set") {
          text = s.text;
          setField(text);
          await sleep(350);
        } else if (s.do === "copied") {
          setCopied(s.text);
          await sleep(700);
        } else if (s.do === "bar") {
          lastBar = s.bar;
          setBar(s.bar);
          await sleep(450);
        } else if (s.do === "act") {
          setWaiting(true);
          const hold = lastBar?.kind === "intent" && lastBar.hold;
          await new Promise<void>((resolve) => {
            actResolve.current = resolve;
            // If the visitor doesn't act, the demo does it after a moment.
            setTimeout(() => {
              if (!alive() || actResolve.current !== resolve) return;
              if (hold) holdTo(act);
              else act();
            }, 2600);
          });
          if (!alive()) return;
          setCopied(null);
          await sleep(250);
        } else if (s.do === "send") {
          const t = s.text ?? text;
          setMsgs((m) => [...m, { id: nextId.current++, me: true, text: t }]);
          text = "";
          setField("");
          setBar({ kind: "words", words: ["I", "the", "on"] });
          await sleep(700);
        } else if (s.do === "wait") {
          await sleep(s.ms);
        }
      }
      await sleep(2600);
      if (alive()) onDone?.();
    })();
    return () => {
      run.current++;
      actResolve.current = null;
      cancelAnimationFrame(holdRaf.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scenario]);

  useEffect(() => {
    chat.current?.scrollTo({ top: chat.current.scrollHeight, behavior: "smooth" });
  }, [msgs]);

  const numbers = /^[\d\s.$]+$/.test(field.slice(-1)) && /\d/.test(field.slice(-1));

  return (
    <div className="phone">
      <div className="screen">
        <div className="island" />
        <div className="status">
          <b>9:41</b>
          <span>●●● ▮</span>
        </div>
        <div className="chat-head">
          <span className="avatar">{scenario.name[0]}</span>
          <b>{scenario.name}</b>
        </div>
        <div className="chat" ref={chat}>
          {msgs.map((m) => (
            <div key={m.id} className={`msg ${m.me ? "me" : "them"}`}>
              {m.text}
            </div>
          ))}
          {copied && <div className="copied">Copied: “{copied}”</div>}
        </div>
        <div className="composer">
          <span className="plus">+</span>
          <span className="input">
            {field || <span className="ph">iMessage</span>}
            <span className="caret" />
          </span>
        </div>
        <div className="kb">
          <BarView bar={bar} holding={holding} onAct={act} onHoldStart={onHoldStart} onHoldEnd={onHoldEnd} hint={waiting} />
          <Keys lit={lit} numbers={numbers} onWallet={act} />
        </div>
      </div>
    </div>
  );
}

export { SCENARIOS };
