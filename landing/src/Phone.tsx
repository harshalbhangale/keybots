import { useCallback, useEffect, useRef, useState } from "react";
import { SCENARIOS, type Panel, type Scenario, type Strip, type Tab } from "./scenarios";

type Msg = { id: number; me: boolean; text: string };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const HOLD_MS = 950;
const TABS: Tab[] = ["ABC", "PAY", "TRADE", "CHECK", "VAULT"];
const tabFor = (p: Panel | null): Tab =>
  !p ? "ABC" : p.kind === "pay" ? "PAY" : p.kind === "trade" ? "TRADE" : p.kind === "check" ? "CHECK" : p.kind === "vault" ? "VAULT" : "ABC";

function I({ n, s = 16 }: { n: string; s?: number }) {
  const p = { width: s, height: s, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 2.2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  switch (n) {
    case "up":
      return <svg {...p}><path d="M7 17 17 7M9 7h8v8" /></svg>;
    case "ok":
      return <svg {...p}><path d="M5 12.5 10 17l9-10" /></svg>;
    case "x":
      return <svg {...p}><path d="M6 6l12 12M18 6 6 18" /></svg>;
    case "down":
      return <svg {...p}><path d="M12 5v14M6 13l6 6 6-6" /></svg>;
    case "back":
      return <svg {...p}><path d="M15 6l-6 6 6 6" /></svg>;
    case "shift":
      return <svg {...p} strokeWidth={1.8}><path d="M12 4 4 12h4v7h8v-7h4z" /></svg>;
    case "del":
      return <svg {...p} strokeWidth={1.8}><path d="M9 6h11v12H9l-6-6zM12.5 9.5l5 5M17.5 9.5l-5 5" /></svg>;
    case "ret":
      return <svg {...p} strokeWidth={1.8}><path d="M19 6v6H6M10 8l-4 4 4 4" /></svg>;
    case "globe":
      return <svg {...p} strokeWidth={1.6}><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18" /></svg>;
    case "mic":
      return <svg {...p} strokeWidth={1.6}><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" /></svg>;
    case "near":
      return <svg {...p} strokeWidth={2.4}><path d="M7 18V6l10 12V6" /></svg>;
    default:
      return null;
  }
}

/** The big lime button: tap, or press and hold until the band fills. */
function Big({ label, hold, fill, hint, onTap, onDown, onUp }: { label: string; hold: boolean; fill: number; hint: boolean; onTap: () => void; onDown: () => void; onUp: () => void }) {
  return (
    <button
      className={`big ${hold ? "hold" : ""} ${hint ? "hint" : ""}`}
      onClick={hold ? undefined : onTap}
      onPointerDown={hold ? onDown : undefined}
      onPointerUp={hold ? onUp : undefined}
      onPointerLeave={hold ? onUp : undefined}
      onContextMenu={(e) => e.preventDefault()}
    >
      {hold && <span className="band" style={{ width: `${fill * 100}%` }} />}
      <span className="lbl">
        {label} <I n="up" s={15} />
      </span>
    </button>
  );
}

function PanelView({ panel, act }: { panel: Panel; act: React.ReactNode }) {
  if (panel.kind === "pay")
    return (
      <div className="panel">
        <div className="ph-row">
          <span className="badge">PAY</span>
          <span className="muted-s">{panel.agent}</span>
        </div>
        <div className="card">
          <div className="leg">
            <span className="tok near">
              <I n="near" s={15} />
            </span>
            <span>
              <small>YOU PAY</small>
              <b className="amt">{panel.amount} NEAR</b>
            </span>
          </div>
          <div className="sep">
            <span className="mid">
              <I n="down" s={12} />
            </span>
          </div>
          <div className="leg">
            <span className="tok who">{panel.to[0].toUpperCase()}</span>
            <span>
              <small>TO</small>
              <b>{panel.to}</b>
            </span>
            {panel.memo && <span className="right muted-s">{panel.memo}</span>}
          </div>
        </div>
        <div className="tiles">
          {panel.checks.map(([k, v]) => (
            <span className="tile" key={k}>
              <small>{k.toUpperCase()}</small>
              <b>{v}</b>
            </span>
          ))}
        </div>
        {act}
      </div>
    );
  if (panel.kind === "trade")
    return (
      <div className="panel">
        <div className="ph-row">
          <span className="badge">BUY</span>
          <span className="muted-s">Trading Agent · quote first</span>
        </div>
        <div className="card">
          <div className="leg">
            <span className="tok usdc">$</span>
            <span>
              <small>YOU PAY</small>
              <b className="amt">
                {panel.pay[0]} {panel.pay[1]}
              </b>
            </span>
            <span className="right muted-s">{panel.pay[2]}</span>
          </div>
          <div className="sep">
            <span className="mid">
              <I n="down" s={12} />
            </span>
          </div>
          <div className="leg">
            <span className="tok near">
              <I n="near" s={15} />
            </span>
            <span>
              <small>YOU GET</small>
              <b className="amt">
                {panel.get[0]} {panel.get[1]}
              </b>
            </span>
            <span className="right muted-s">{panel.get[2]}</span>
          </div>
        </div>
        <div className="tiles">
          {panel.tiles.map(([k, v]) => (
            <span className="tile" key={k}>
              <small>{k.toUpperCase()}</small>
              <b>{v}</b>
            </span>
          ))}
        </div>
        {act}
      </div>
    );
  if (panel.kind === "check")
    return (
      <div className="panel">
        <div className="ph-row">
          <span className="badge amber">CHECK</span>
          <span className="muted-s">{panel.button}</span>
        </div>
        <div className="quote">“{panel.copied}”</div>
        <div className="trace">
          {panel.trace.map(([r, l, st], i) => (
            <div className={`tr ${st}`} key={r} style={{ animationDelay: `${i * 0.35}s` }}>
              <code>{r}</code>
              <span>{l}</span>
              <span className="st">{st === "pass" ? <I n="ok" s={13} /> : <I n="x" s={13} />}</span>
            </div>
          ))}
        </div>
      </div>
    );
  if (panel.kind === "vault")
    return (
      <div className="panel">
        <div className="ph-row">
          <span className="badge">VAULT</span>
          <span className="muted-s">Addresses only · never keys</span>
        </div>
        {panel.items.map(([k, v]) => (
          <div className="vault-row" key={k}>
            <span className="tok near">
              <I n="near" s={15} />
            </span>
            <span>
              <small>{k.toUpperCase()}</small>
              <b>{v}</b>
            </span>
          </div>
        ))}
        {act}
      </div>
    );
  return (
    <div className={`panel done ${panel.tone}`}>
      <span className="ring">
        <I n={panel.tone === "blocked" ? "x" : "ok"} s={30} />
      </span>
      <b className="done-t">{panel.title}</b>
      <span className="muted-s">{panel.sub}</span>
      {panel.tx && <code className="tx">tx {panel.tx} ↗</code>}
    </div>
  );
}

const ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];

function Keys({ lit }: { lit: string }) {
  return (
    <div className="keys" aria-hidden>
      {ROWS.map((r, ri) => (
        <div className={`krow r${ri}`} key={ri}>
          {ri === 2 && (
            <span className="k fn">
              <I n="shift" s={18} />
            </span>
          )}
          {r.split("").map((c) => (
            <span key={c} className={`k ${lit === c ? "lit" : ""} ${c === "p" ? "tab" : ""}`}>
              {c}
              {lit === c && <span className="pop">{c}</span>}
            </span>
          ))}
          {ri === 2 && (
            <span className="k fn">
              <I n="del" s={18} />
            </span>
          )}
        </div>
      ))}
      <div className="krow r3">
        <span className="k fn w">123</span>
        <span className={`k space ${lit === " " ? "lit" : ""}`}>AIRKEY</span>
        <span className="k fn w">
          <I n="ret" s={18} />
        </span>
      </div>
    </div>
  );
}

/** A chat with the AIRKEY keyboard. It plays a scenario; the visitor can tap or hold the lime button. */
export default function Phone({ scenario, onDone }: { scenario: Scenario; onDone?: () => void }) {
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [field, setField] = useState("");
  const [strip, setStrip] = useState<Strip>({ kind: "words", words: ["I", "the", "on"] });
  const [panel, setPanel] = useState<Panel | null>(null);
  const [lit, setLit] = useState("");
  const [fill, setFill] = useState(0);
  const [waiting, setWaiting] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const resolver = useRef<(() => void) | null>(null);
  const raf = useRef(0);
  const run = useRef(0);
  const chat = useRef<HTMLDivElement>(null);
  const nextId = useRef(1);

  const act = useCallback(() => {
    const r = resolver.current;
    if (!r) return;
    resolver.current = null;
    setWaiting(false);
    r();
  }, []);

  const startHold = useCallback(() => {
    if (!resolver.current) return;
    cancelAnimationFrame(raf.current);
    const t0 = performance.now();
    const tick = () => {
      const k = Math.min(1, (performance.now() - t0) / HOLD_MS);
      setFill(k);
      if (k >= 1) {
        act();
        setTimeout(() => setFill(0), 250);
      } else raf.current = requestAnimationFrame(tick);
    };
    raf.current = requestAnimationFrame(tick);
  }, [act]);

  const endHold = useCallback(() => {
    cancelAnimationFrame(raf.current);
    setFill((f) => (f >= 1 ? f : 0));
  }, []);

  useEffect(() => {
    const id = ++run.current;
    const alive = () => run.current === id;
    setMsgs([]);
    setField("");
    setCopied(null);
    setPanel(null);
    setStrip({ kind: "words", words: ["I", "the", "on"] });
    let text = "";
    let cur: Panel | null = null;

    (async () => {
      await sleep(500);
      for (const s of scenario.steps) {
        if (!alive()) return;
        switch (s.do) {
          case "them":
            await sleep(300);
            setMsgs((m) => [...m, { id: nextId.current++, me: false, text: s.text }]);
            await sleep(950);
            break;
          case "type":
            for (const ch of s.text) {
              if (!alive()) return;
              text += ch;
              setField(text);
              setLit(ch.toLowerCase());
              await sleep(ch === " " ? 120 : 60 + Math.random() * 60);
            }
            setLit("");
            await sleep(300);
            break;
          case "set":
            text = s.text;
            setField(text);
            await sleep(350);
            break;
          case "copied":
            setCopied(s.text);
            await sleep(700);
            break;
          case "strip":
            setStrip(s.strip);
            await sleep(400);
            break;
          case "panel":
            cur = s.panel;
            setPanel(s.panel);
            await sleep(500);
            break;
          case "keys":
            cur = null;
            setPanel(null);
            setStrip({ kind: "words", words: ["I", "the", "on"] });
            await sleep(400);
            break;
          case "act": {
            setWaiting(true);
            const hold = !!cur && (cur.kind === "pay" || cur.kind === "trade");
            await new Promise<void>((resolve) => {
              resolver.current = resolve;
              setTimeout(() => {
                if (!alive() || resolver.current !== resolve) return;
                if (hold) startHold();
                else act();
              }, 2800);
            });
            if (!alive()) return;
            setCopied(null);
            await sleep(200);
            break;
          }
          case "send": {
            const t = s.text ?? text;
            setMsgs((m) => [...m, { id: nextId.current++, me: true, text: t }]);
            text = "";
            setField("");
            setStrip({ kind: "words", words: ["I", "the", "on"] });
            await sleep(700);
            break;
          }
          case "wait":
            await sleep(s.ms);
            break;
        }
      }
      await sleep(2600);
      if (alive()) onDone?.();
    })();

    return () => {
      run.current++;
      resolver.current = null;
      cancelAnimationFrame(raf.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scenario]);

  useEffect(() => {
    chat.current?.scrollTo({ top: chat.current.scrollHeight, behavior: "smooth" });
  }, [msgs, copied]);

  const holdable = !!panel && (panel.kind === "pay" || panel.kind === "trade");
  const actBtn =
    panel && panel.kind === "pay" ? (
      <Big label={panel.button} hold fill={fill} hint={waiting} onTap={act} onDown={startHold} onUp={endHold} />
    ) : panel && panel.kind === "trade" ? (
      <Big label={panel.button} hold fill={fill} hint={waiting} onTap={act} onDown={startHold} onUp={endHold} />
    ) : panel && panel.kind === "vault" ? (
      <Big label="Insert address" hold={false} fill={0} hint={waiting} onTap={act} onDown={() => {}} onUp={() => {}} />
    ) : null;
  const active = tabFor(panel);

  return (
    <div className="phone">
      <div className="screen">
        <div className="island" />
        <div className="status">
          <b>9:41</b>
          <span className="sig">
            <i />
            <i />
            <i />
            <i />
            <em />
          </span>
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
          {copied && <div className="copied">Copied</div>}
        </div>
        <div className="composer">
          <span className="plus">+</span>
          <span className="input">
            {field || <span className="ph">Message</span>}
            <span className="caret" />
          </span>
        </div>

        <div className="kb">
          <div className="tabs-row">
            <span className="brandkey">
              A<i />
            </span>
            <div className="ktabs">
              {TABS.slice(1).map((t) => (
                <span key={t} className={active === t ? "on" : ""}>
                  {t}
                </span>
              ))}
            </div>
          </div>

          <div className="body">
            {panel ? (
              <div className="panel-wrap" key={panel.kind + ("title" in panel ? panel.title : "")}>
                <PanelView panel={panel} act={actBtn} />
              </div>
            ) : (
              <>
                {strip.kind === "words" ? (
                  <div className="strip words">
                    {strip.words.map((w, i) => (
                      <span key={i}>{w}</span>
                    ))}
                  </div>
                ) : (
                  <div className="strip chip" key={strip.title}>
                    <span className="dot">
                      <I n="up" s={14} />
                    </span>
                    <span className="txt">
                      <b>{strip.title}</b>
                      <small>{strip.sub}</small>
                    </span>
                    <button className={`go ${waiting ? "hint" : ""}`} onClick={act}>
                      {strip.action}
                    </button>
                  </div>
                )}
                <Keys lit={lit} />
              </>
            )}
          </div>
          <div className="sys">
            <I n="globe" s={22} />
            <I n="mic" s={22} />
          </div>
        </div>
      </div>
      {holdable && <span className="sr-only">Press and hold the lime button</span>}
    </div>
  );
}

export { SCENARIOS };
