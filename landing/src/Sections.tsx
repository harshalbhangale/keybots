import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import Phone, { I } from "./Phone";
import { SCENARIOS } from "./scenarios";

type Vars = CSSProperties & Record<`--${string}`, string | number>;

/* ---------- hero backdrop: a giant AIRKEY keyboard, keys lighting up ---------- */

const BIG_ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
const DOTS = new Set(["p", "s", "v", "c", "f", "t"]);

export function Backdrop() {
  const [lit, setLit] = useState<string[]>([]);
  useEffect(() => {
    const letters = BIG_ROWS.join("").split("");
    const id = setInterval(() => {
      const word = ["pay", "near", "swap", "vault", "check", "follow"][Math.floor(Math.random() * 6)];
      let i = 0;
      const t = setInterval(() => {
        setLit([word[i]]);
        if (++i >= word.length) {
          clearInterval(t);
          setTimeout(() => setLit([]), 260);
        }
      }, 170);
      void letters;
    }, 2600);
    return () => clearInterval(id);
  }, []);
  return (
    <div className="backdrop" aria-hidden>
      {BIG_ROWS.map((r, ri) => (
        <div className={`brow b${ri}`} key={r}>
          {r.split("").map((c) => (
            <span key={c} className={`bk ${lit.includes(c) ? "on" : ""}`}>
              {c}
              {DOTS.has(c) && <i />}
            </span>
          ))}
        </div>
      ))}
      <div className="brow b3">
        <span className="bk w">123</span>
        <span className="bk space">AIRKEY</span>
        <span className="bk w">go</span>
      </div>
    </div>
  );
}

/* ---------- the sticker field ---------- */

type Float = { x: number; y: number; d: number; r: number; t: number; el: ReactNode; desk?: boolean };

const Key = ({ k }: { k: string }) => (
  <span className="st-key">
    {k}
    <i />
  </span>
);
const App = ({ bg, children }: { bg: string; children: ReactNode }) => (
  <span className="st-app" style={{ background: bg }}>
    {children}
  </span>
);

const FLOATS: Float[] = [
  { x: 6, y: 8, d: 0.9, r: -8, t: 6, el: <span className="st-bubble them">you owe me for dinner 🍜</span> },
  { x: 34, y: 2, d: 0.6, r: 5, t: 7, el: <span className="st-bubble me">pay harshal 0.2</span> },
  { x: 64, y: 0, d: 1.1, r: 0, t: 8, el: <span className="st-coin"><I n="near" s={30} /></span> },
  { x: 88, y: 10, d: 0.7, r: 10, t: 6.5, el: <App bg="linear-gradient(160deg,#c6f25a,#8fc12c)"><I n="wallet" s={26} /></App> },
  { x: 2, y: 34, d: 1.2, r: -6, t: 7.5, el: <Key k="P" /> },
  { x: 14, y: 52, d: 0.8, r: 8, t: 6, el: <App bg="linear-gradient(160deg,#3b82f6,#1d4ed8)"><span style={{ fontWeight: 800, fontSize: 18 }}>文A</span></App>, desk: true },
  { x: 4, y: 74, d: 1, r: -4, t: 8, el: <span className="st-chip red"><b>Blocked</b> R4 · drain.near</span> },
  { x: 26, y: 84, d: 0.6, r: 6, t: 6.8, el: <Key k="S" />, desk: true },
  { x: 40, y: 72, d: 1.3, r: -3, t: 7, el: <span className="st-note">split 236 / 4<br />= 59 each</span> },
  { x: 60, y: 84, d: 0.8, r: 4, t: 7.4, el: <span className="st-chip lime"><I n="ok" s={14} /> Paid 0.2 NEAR</span> },
  { x: 82, y: 70, d: 1.1, r: -9, t: 6.2, el: <App bg="#111"><span style={{ fontSize: 26 }}>🐋</span></App> },
  { x: 90, y: 40, d: 0.7, r: 7, t: 7.8, el: <Key k="V" /> },
  { x: 74, y: 24, d: 1, r: -5, t: 6.6, el: <span className="st-chip"><span className="up">▲</span> NEAR $3.39</span>, desk: true },
  { x: 80, y: 90, d: 0.9, r: 3, t: 7.2, el: <span className="st-chip">@nearwhale · 70% hit</span>, desk: true },
  { x: 50, y: 92, d: 0.5, r: -7, t: 8.4, el: <Key k="C" />, desk: true },
];

export function Stickers({ children }: { children: ReactNode }) {
  const stage = useRef<HTMLDivElement>(null);
  const drag = useRef<{ el: HTMLElement; id: number; sx: number; sy: number; ox: number; oy: number } | null>(null);
  const z = useRef(10);

  const lean = (e: React.PointerEvent<HTMLDivElement>) => {
    const el = stage.current;
    if (!el || e.pointerType === "touch" || drag.current) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty("--px", (((e.clientX - r.left) / r.width) * 2 - 1).toFixed(3));
    el.style.setProperty("--py", (((e.clientY - r.top) / r.height) * 2 - 1).toFixed(3));
  };
  const grab = (e: React.PointerEvent<HTMLSpanElement>) => {
    if (e.button !== 0) return;
    const el = e.currentTarget;
    el.style.left = `${el.offsetLeft}px`;
    el.style.top = `${el.offsetTop}px`;
    el.style.zIndex = String(++z.current);
    el.setPointerCapture(e.pointerId);
    el.classList.add("held");
    drag.current = { el, id: e.pointerId, sx: e.clientX, sy: e.clientY, ox: el.offsetLeft, oy: el.offsetTop };
    e.preventDefault();
  };
  const carry = (e: React.PointerEvent<HTMLSpanElement>) => {
    const d = drag.current;
    if (!d || d.id !== e.pointerId) return;
    d.el.style.left = `${d.ox + e.clientX - d.sx}px`;
    d.el.style.top = `${d.oy + e.clientY - d.sy}px`;
  };
  const drop = (e: React.PointerEvent<HTMLSpanElement>) => {
    const d = drag.current;
    if (!d || d.id !== e.pointerId) return;
    d.el.classList.remove("held");
    drag.current = null;
  };

  return (
    <div className="st-stage" ref={stage} onPointerMove={lean} onPointerLeave={() => (stage.current?.style.setProperty("--px", "0"), stage.current?.style.setProperty("--py", "0"))}>
      <div className="st-field" aria-hidden>
        {FLOATS.map((f, i) => (
          <span
            key={i}
            className={`st ${f.desk ? "desk" : ""}`}
            style={{ left: `${f.x}%`, top: `${f.y}%` }}
            onPointerDown={grab}
            onPointerMove={carry}
            onPointerUp={drop}
            onPointerCancel={drop}
          >
            <span className="st-par" style={{ "--d": f.d } as Vars}>
              <span className="st-float" style={{ "--r": `${f.r}deg`, "--t": `${f.t}s`, animationDelay: `${-i * 0.7}s` } as Vars}>
                {f.el}
              </span>
            </span>
          </span>
        ))}
      </div>
      {children}
    </div>
  );
}

/* ---------- feature cards ---------- */

const HOLDS = [
  { k: "P", label: "Pay", result: "Pay 0.2 NEAR to harshal" },
  { k: "S", label: "Swap", result: "Swap 1 NEAR → USDC" },
  { k: "V", label: "Vault", result: "airkey-harshal.testnet" },
  { k: "C", label: "Check", result: "Check what you copied" },
  { k: "F", label: "Follow", result: "Follow @nearwhale" },
];

const TOOLS = [
  { icon: "↗", label: "Pay", line: "Pay harshal 0.2 NEAR" },
  { icon: "▲", label: "Price", line: "NEAR $3.39 · live" },
  { icon: "⇄", label: "Swap", line: "Buy $2 of NEAR" },
  { icon: "◷", label: "Order", line: "Sell 1 NEAR below $2" },
  { icon: "文", label: "Translate", line: "see you tomorrow → hasta mañana" },
  { icon: "✦", label: "AI", line: "Tidy this up · NEAR AI" },
];

function spot(e: React.PointerEvent<HTMLElement>) {
  const r = e.currentTarget.getBoundingClientRect();
  e.currentTarget.style.setProperty("--mx", `${e.clientX - r.left}px`);
  e.currentTarget.style.setProperty("--my", `${e.clientY - r.top}px`);
}

export function Features() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => el.classList.toggle("live", e.isIntersecting), { rootMargin: "80px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <div className="feats" ref={ref}>
      <article className="feat" onPointerMove={spot}>
        <div className="fv">
          <div className="hold-results">
            {HOLDS.map((h, i) => (
              <span key={h.k} className="hold-result" style={{ "--i": i } as Vars}>
                {h.result}
              </span>
            ))}
          </div>
          <div className="hold-keys">
            {HOLDS.map((h, i) => (
              <span key={h.k} className="hold" style={{ "--i": i } as Vars}>
                <span className="hk">
                  {h.k}
                  <i />
                  <svg className="hring" viewBox="0 0 60 60"><rect x="2" y="2" width="56" height="56" rx="14" /></svg>
                </span>
                <small>{h.label}</small>
              </span>
            ))}
          </div>
        </div>
        <h3>Hold a key. It acts.</h3>
      </article>

      <article className="feat" onPointerMove={spot}>
        <div className="fv">
          <div className="tool-lines">
            {TOOLS.map((t, i) => (
              <span key={t.label} className="tool-line" style={{ "--i": i } as Vars}>
                <b>{t.icon}</b>
                {t.line}
              </span>
            ))}
          </div>
          <div className="tool-strip">
            <span className="tool-a">A<i /></span>
            <span className="tool-icons">
              <span className="tool-hl" />
              {TOOLS.map((t, i) => (
                <span key={t.label} className="tool-i" style={{ "--i": i } as Vars}>
                  {t.icon}
                </span>
              ))}
            </span>
          </div>
        </div>
        <h3>AI and NEAR, inside the keyboard.</h3>
      </article>

      <article className="feat" onPointerMove={spot}>
        <div className="fv">
          <div className="rules-mini">
            {[
              ["R1", "Kill switch", "pass"],
              ["R3", "Blocklist", "pass"],
              ["R4", "Over 0.5 NEAR", "fire"],
            ].map(([r, l, s], i) => (
              <span key={r} className={`rm ${s}`} style={{ "--i": i } as Vars}>
                <code>{r}</code>
                {l}
                <b>{s === "pass" ? "✓" : "✕"}</b>
              </span>
            ))}
            <span className="rm-verdict">Blocked. Nothing moved.</span>
          </div>
        </div>
        <h3>The leash says no.</h3>
      </article>
    </div>
  );
}

/* ---------- KOL following ---------- */

const CALLERS = [
  { emoji: "🐋", name: "NEAR Whale", handle: "@nearwhale", hits: 14, calls: 20, last: "$NEAR long · target $4" },
  { emoji: "🦉", name: "Intents Maxi", handle: "@intentsmaxi", hits: 9, calls: 16, last: "$SOL short · below $140" },
  { emoji: "🎯", name: "Chain Sniper", handle: "@chainsniper", hits: 5, calls: 18, last: "$ETH long · deleted 2 calls" },
];

export function Callers() {
  const [following, setFollowing] = useState<string[]>(["@nearwhale"]);
  return (
    <div className="callers">
      {CALLERS.map((c, i) => {
        const pct = Math.round((c.hits / c.calls) * 100);
        const on = following.includes(c.handle);
        return (
          <div className="caller-card" key={c.handle} data-reveal style={{ transitionDelay: `${i * 0.08}s` }} onPointerMove={spot}>
            <div className="cc-top">
              <span className="cc-av">{c.emoji}</span>
              <span className="cc-id">
                <b>{c.name}</b>
                <small>{c.handle}</small>
              </span>
              <span className={`cc-pct ${pct >= 60 ? "good" : pct < 40 ? "bad" : ""}`}>{pct}%</span>
            </div>
            <div className="cc-spark">
              {Array.from({ length: c.calls }, (_, k) => (
                <i key={k} className={(k * 7) % c.calls < c.hits ? "hit" : "miss"} style={{ animationDelay: `${k * 0.04}s` }} />
              ))}
            </div>
            <div className="cc-meta">
              <span>{c.hits} of {c.calls} calls hit</span>
              <span>Last: {c.last}</span>
            </div>
            <button className={`cc-follow ${on ? "on" : ""}`} onClick={() => setFollowing((f) => (on ? f.filter((h) => h !== c.handle) : [...f, c.handle]))}>
              {on ? "Following · copies inside your caps" : "Follow"}
            </button>
          </div>
        );
      })}
    </div>
  );
}

/* ---------- works with ---------- */

export const WORKS = ["NEAR Protocol", "NEAR Intents", "1Click swaps", "NEAR AI Cloud", "USDC", "Nearblocks", "Face ID", "Contacts", "Messages", "Any chat app"];

/* ---------- try it here ---------- */

export function Try() {
  const [i, setI] = useState(0);
  const s = SCENARIOS[i];
  return (
    <div className="try">
      <div className="try-left">
        <h2 className="try-h" key={s.id}>
          <span>{s.headline[0]}</span>
          <span className="lime">{s.headline[1]}</span>
        </h2>
        <div className="chats">
          {SCENARIOS.map((c, k) => (
            <button key={c.id} className={`chat-row ${k === i ? "on" : ""}`} onClick={() => setI(k)}>
              <span className="cr-av">{c.emoji}</span>
              <span className="cr-txt">
                <span className="cr-top">
                  <b>{c.who}</b>
                  <small>{c.tag}</small>
                  {c.soon && <em>Soon</em>}
                </span>
                <span className="cr-prev">{c.preview}</span>
              </span>
            </button>
          ))}
        </div>
      </div>
      <div className="try-right">
        <Phone scenario={s} onDone={() => setI((x) => (x + 1) % SCENARIOS.length)} />
        <p className="tip">Hold the lime button, or let it play.</p>
      </div>
    </div>
  );
}
