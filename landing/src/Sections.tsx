import { useEffect, useRef, useState, type CSSProperties } from "react";
import Phone from "./Phone";
import { CHAIN, SCENARIOS } from "./scenarios";

type Vars = CSSProperties & Record<`--${string}`, string | number>;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** The NEAR mark, drawn for this page. */
export function NearMark({ size = "0.8em" }: { size?: string | number }) {
  return (
    <span className="near-mark" style={{ width: size, height: size }} aria-label="NEAR">
      <svg viewBox="0 0 20.2 19.6" aria-hidden>
        <path
          d="M15.3 1.4 11.6 6.9c-.3.4.3.9.6.6l3.7-3.2c.1-.1.3 0 .3.1v9.9c0 .2-.2.2-.3.1L4.7.6C4.3.2 3.8 0 3.2 0h-.4C1.3 0 0 1.3 0 2.8v13.9c0 1.6 1.3 2.8 2.8 2.8.9 0 1.8-.5 2.3-1.3l3.7-5.5c.3-.4-.3-.9-.6-.6l-3.7 3.2c-.1.1-.3 0-.3-.1V5.4c0-.2.2-.2.3-.1l11.2 13.6c.4.4 1 .6 1.5.6h.4c1.6 0 2.8-1.3 2.8-2.8V2.8C20.2 1.3 18.9 0 17.4 0c-1 0-1.9.5-2.4 1.4z"
          fill="currentColor"
        />
      </svg>
    </span>
  );
}

/* ---------- hero: one command bar that turns words into results ---------- */

const LINES: { type: string; tone: "paid" | "blocked" | "info"; result: string; meta: string }[] = [
  { type: "pay harshal 0.2 for dinner", tone: "paid", result: "Paid 0.2 NEAR to harshal.near", meta: "tx HRhR7pS9…" },
  { type: "$near", tone: "info", result: "NEAR $3.39", meta: "live · NEAR Intents" },
  { type: "Send 5 NEAR to drain.near", tone: "blocked", result: "Blocked by the leash · R4", meta: "over the 0.5 cap" },
  { type: "buy $2 of near", tone: "paid", result: "Quoted 0.5861 NEAR", meta: "inside your 1 NEAR cap" },
];

export function HeroBar() {
  const [text, setText] = useState("");
  const [res, setRes] = useState<(typeof LINES)[number] | null>(null);
  useEffect(() => {
    let alive = true;
    (async () => {
      await sleep(900);
      for (let i = 0; alive; i = (i + 1) % LINES.length) {
        const l = LINES[i];
        setRes(null);
        for (let k = 1; k <= l.type.length && alive; k++) {
          setText(l.type.slice(0, k));
          await sleep(45 + Math.random() * 45);
        }
        await sleep(500);
        if (!alive) return;
        setRes(l);
        await sleep(2400);
        setText("");
      }
    })();
    return () => {
      alive = false;
    };
  }, []);
  return (
    <div className="hbar" aria-live="polite">
      <div className={`hbar-in ${res ? "done " + res.tone : ""}`}>
        {res ? (
          <span className="hbar-res" key={res.result}>
            <span className="hb-ico">{res.tone === "blocked" ? "✕" : res.tone === "paid" ? "✓" : "▲"}</span>
            <b>{res.result}</b>
            <small>{res.meta}</small>
          </span>
        ) : (
          <span className="hbar-text">
            {text}
            <span className="hb-caret" />
          </span>
        )}
      </div>
    </div>
  );
}

/* ---------- try it: the keyboard, and what happens on NEAR ---------- */

export function Try() {
  const [i, setI] = useState(0);
  const s = SCENARIOS[i];
  const chain = CHAIN[s.id] ?? [];
  return (
    <div className="try">
      <div className="pills" role="tablist" aria-label="Pick a chat">
        {SCENARIOS.map((c, k) => (
          <button key={c.id} role="tab" aria-selected={k === i} className={k === i ? "on" : ""} onClick={() => setI(k)}>
            <span>{c.emoji}</span> {c.tag}
            {c.soon && <em>Soon</em>}
          </button>
        ))}
      </div>
      <div className="try-grid">
        <div className="try-phone">
          <Phone scenario={s} onDone={() => setI((x) => (x + 1) % SCENARIOS.length)} />
        </div>
        <div className="console" key={s.id}>
          <div className="console-head">
            <NearMark size={18} />
            <b>On NEAR</b>
            <span>{s.soon ? "preview" : "testnet"}</span>
          </div>
          <h3 className="console-title">
            {s.headline[0]} <span className="lime">{s.headline[1]}</span>
          </h3>
          <ol className="console-lines">
            {chain.map(([t, k], n) => (
              <li key={n} className={k} style={{ "--n": n } as Vars}>
                <i>{k === "ok" ? "✓" : k === "fail" ? "✕" : "›"}</i>
                {t}
              </li>
            ))}
          </ol>
          <p className="console-foot">Hold the lime button on the keyboard, or let it play.</p>
        </div>
      </div>
    </div>
  );
}

/* ---------- three cards ---------- */

function spot(e: React.PointerEvent<HTMLElement>) {
  const r = e.currentTarget.getBoundingClientRect();
  e.currentTarget.style.setProperty("--mx", `${e.clientX - r.left}px`);
  e.currentTarget.style.setProperty("--my", `${e.clientY - r.top}px`);
}

const HOLDS = [
  { k: "P", label: "Pay", result: "Pay 0.2 NEAR to harshal" },
  { k: "S", label: "Swap", result: "Swap 1 NEAR → USDC" },
  { k: "V", label: "Vault", result: "airkey-harshal.testnet" },
  { k: "C", label: "Check", result: "Check what you copied" },
  { k: "F", label: "Follow", result: "Follow @nearwhale" },
];

export function Cards() {
  const ref = useRef<HTMLDivElement>(null);
  const [following, setFollowing] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => el.classList.toggle("live", e.isIntersecting), { rootMargin: "80px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <div className="feats" ref={ref}>
      <article className="feat" onPointerMove={spot} data-reveal>
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
                  <svg className="hring" viewBox="0 0 60 60">
                    <rect x="2" y="2" width="56" height="56" rx="14" />
                  </svg>
                </span>
                <small>{h.label}</small>
              </span>
            ))}
          </div>
        </div>
        <h3>Hold a key. It acts.</h3>
        <p>Pay, swap, check or share, without leaving the chat.</p>
      </article>

      <article className="feat" onPointerMove={spot} data-reveal style={{ transitionDelay: "0.08s" }}>
        <span className="pill-soon">Soon</span>
        <div className="fv">
          <div className="mini-caller">
            <div className="mc-top">
              <span className="mc-av">🐋</span>
              <span className="mc-id">
                <b>NEAR Whale</b>
                <small>@nearwhale · $NEAR long</small>
              </span>
              <span className="mc-pct">70%</span>
            </div>
            <div className="mc-spark">
              {Array.from({ length: 20 }, (_, k) => (
                <i key={k} className={(k * 7) % 20 < 14 ? "hit" : "miss"} style={{ "--k": k } as Vars} />
              ))}
            </div>
            <button className={`mc-follow ${following ? "on" : ""}`} onClick={() => setFollowing((f) => !f)}>
              {following ? "✓ Following inside your caps" : "Follow"}
            </button>
          </div>
        </div>
        <h3>Follow the callers who are right.</h3>
        <p>Every call scored on NEAR. Copy the good ones.</p>
      </article>

      <article className="feat" onPointerMove={spot} data-reveal style={{ transitionDelay: "0.16s" }}>
        <div className="fv">
          <div className="rules-mini">
            {[
              ["R1", "Kill switch", "pass"],
              ["R3", "Blocklist", "pass"],
              ["R4", "Over 0.5 NEAR", "fire"],
            ].map(([r, l, st], i) => (
              <span key={r} className={`rm ${st}`} style={{ "--i": i } as Vars}>
                <code>{r}</code>
                {l}
                <b>{st === "pass" ? "✓" : "✕"}</b>
              </span>
            ))}
            <span className="rm-verdict">Blocked. Nothing moved.</span>
          </div>
        </div>
        <h3>The leash says no.</h3>
        <p>A NEAR contract holds the money and checks your rules first.</p>
      </article>
    </div>
  );
}
