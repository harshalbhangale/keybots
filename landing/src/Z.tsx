import { useEffect, useRef, useState, type CSSProperties } from "react";

type Vars = CSSProperties & Record<`--${string}`, string | number>;
const TX = (h: string) => `https://testnet.nearblocks.io/txns/${h}`;

function spot(e: React.PointerEvent<HTMLElement>) {
  const r = e.currentTarget.getBoundingClientRect();
  e.currentTarget.style.setProperty("--mx", `${e.clientX - r.left}px`);
  e.currentTarget.style.setProperty("--my", `${e.clientY - r.top}px`);
}

/* ---------- the keyboard does all of this ---------- */

export function Bento() {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => el.classList.toggle("live", e.isIntersecting), { rootMargin: "100px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return (
    <div className="z-bento" ref={ref}>
      <article className="z-tile wide" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-pay">
            <span className="v-field">pay harshal 0.2 for dinner</span>
            <span className="v-hold"><i /><b>Hold to pay</b></span>
            <span className="v-paid">✓ Paid 0.2 NEAR · harshal.near</span>
          </div>
        </div>
        <h3>Hold to pay.</h3>
        <p>Type it, hold the button, done. A stray tap in a chat never moves money.</p>
      </article>

      <article className="z-tile" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-rules">
            <span className="ok">R1 kill switch</span>
            <span className="ok">R3 blocklist</span>
            <span className="no">R4 over 0.5 NEAR</span>
          </div>
        </div>
        <h3>Scams hit a wall.</h3>
        <p>Pasted words go to an agent that can't pay strangers. The contract blocks the rest.</p>
      </article>

      <article className="z-tile" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-face">
            <svg viewBox="0 0 48 48" aria-hidden><path d="M6 16V10a4 4 0 0 1 4-4h6M32 6h6a4 4 0 0 1 4 4v6M42 32v6a4 4 0 0 1-4 4h-6M16 42h-6a4 4 0 0 1-4-4v-6" /><path d="M17 18v3M31 18v3M24 18v8h-2M18 32c3.5 3 8.5 3 12 0" /></svg>
            <small>Approve 0.3 NEAR to designer.near</small>
          </div>
        </div>
        <h3>New receiver? You decide.</h3>
        <p>It waits on chain until you approve with Face ID.</p>
      </article>

      <article className="z-tile" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-swap"><span className="tn">N</span><span className="flow" /><span className="tu">$</span></div>
          <small className="v-cap">0.1 NEAR → 0.2101 USDC</small>
        </div>
        <h3>Swap on NEAR.</h3>
        <p>"swap 0.1 near to usdc" runs on Rhea, inside the Trading Agent's caps.</p>
      </article>

      <article className="z-tile wide" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-call">
            <span className="c1">“NEAR long here, target $4 🚀”</span>
            <span className="c2">Copied</span>
            <span className="c3"><b>Trade NEAR?</b><small>token checked · inside caps</small></span>
          </div>
        </div>
        <h3>Copy a call. Check it. Trade it.</h3>
        <p>Copy a call from any chat. The keyboard reads it, checks the token, and offers the trade.</p>
      </article>

      <article className="z-tile" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-tools">
            {["$near", "236 ÷ 4", "100 usd→inr", "vault"].map((t, i) => (
              <span key={t} style={{ "--i": i } as Vars}>{t}</span>
            ))}
          </div>
        </div>
        <h3>Smart chips.</h3>
        <p>Live prices, sums, bill splits, currency and your vault, right in the bar.</p>
      </article>

      <article className="z-tile" onPointerMove={spot} data-reveal>
        <div className="z-vis">
          <div className="v-kill"><span className="sw" /><small>Kill switch</small></div>
        </div>
        <h3>One kill switch.</h3>
        <p>Flip it and every agent stops. The contract enforces it.</p>
      </article>
    </div>
  );
}

/* ---------- follow and auto-trade: coming next ---------- */

const ACCOUNTS = [
  { n: "@nearwhale", h: "NEAR Whale", hits: "14 of 20" },
  { n: "@intentsmaxi", h: "Intents Maxi", hits: "9 of 16" },
  { n: "@chainsniper", h: "Chain Sniper", hits: "5 of 18" },
];

export function Follow() {
  const [on, setOn] = useState<string[]>(["@nearwhale"]);
  const [k, setK] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setK((x) => x + 1), 3200);
    return () => clearInterval(id);
  }, []);
  const calls = ["$NEAR long, target $4", "$SOL short below $140", "$ETH long here"];
  return (
    <div className="z-follow">
      <div className="z-follow-copy" data-reveal>
        <span className="z-next">Coming next · not built yet</span>
        <h2>Follow callers. <span className="grad">Their calls become your trades.</span></h2>
        <ol>
          <li><b>Connect X.</b> Pick the accounts you follow.</li>
          <li><b>Their calls are read</b> and checked, like a call you copy yourself.</li>
          <li><b>Trades run on their own,</b> only inside the caps your leash enforces.</li>
        </ol>
        <p className="z-note">Today you copy a call yourself and hold to trade. Auto-trading from followed accounts is the next build.</p>
      </div>
      <div className="z-follow-card" data-reveal>
        <div className="zf-head"><span>Following</span><i>preview</i></div>
        {ACCOUNTS.map((a) => {
          const f = on.includes(a.n);
          return (
            <div className="zf-row" key={a.n}>
              <span className="zf-av">{a.h[0]}</span>
              <span className="zf-id"><b>{a.h}</b><small>{a.n} · {a.hits} calls hit</small></span>
              <button className={`zf-btn ${f ? "on" : ""}`} onClick={() => setOn((x) => (f ? x.filter((y) => y !== a.n) : [...x, a.n]))}>
                {f ? "Following" : "Follow"}
              </button>
            </div>
          );
        })}
        <div className="zf-feed">
          <span className="zf-feed-t">Incoming call</span>
          <div className="zf-call" key={k}>
            <b>{ACCOUNTS[k % 3].n}</b> {calls[k % 3]}
            <span className={`zf-act ${on.includes(ACCOUNTS[k % 3].n) ? "go" : "skip"}`}>
              {on.includes(ACCOUNTS[k % 3].n) ? "Trade inside your caps" : "Not followed: ignored"}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------- works with, and the proof ticker ---------- */

export const WORKS = ["NEAR", "NEAR Intents", "Rhea", "NEAR AI Cloud", "USDC", "Face ID", "Messages", "Any chat app"];

const EVENTS: { t: string; tone: "paid" | "blocked" | "pending"; h: string }[] = [
  { t: "paid 0.2 NEAR → harshal.near", tone: "paid", h: "8yfavh6Ve4Sbyq55XxHjT3ARiU7MGDwVyFpyHoWaviek" },
  { t: "blocked 5 NEAR → drain.near · R4", tone: "blocked", h: "HMeo4MYzcLWXSpkt9sn9qbnXBFfax4fC24nf2BHzD2kt" },
  { t: "waiting for you 0.3 NEAR → designer · R7", tone: "pending", h: "GnS1FeRNoGiNQSkaEW62xSaAwJkMPYAbJS4XzmGEYy52" },
  { t: "approved with Face ID", tone: "paid", h: "34yxQfVFKN9gytQoNYy74wChike3iMN3BdT63ejd6noJ" },
  { t: "swapped on Rhea (testnet)", tone: "paid", h: "4gMJo7Awi9jyb3iVo3981gJJt5Buy5A1jUTyrf8VZ9MS" },
  { t: "copied call traded (testnet)", tone: "paid", h: "7XUq6MLFCiPL15FynnKsyWp9KCx6Ki7pc2WsgTDqRUey" },
  { t: "kill switch on: blocked · R1", tone: "blocked", h: "GDpBrrw3L6DNfAbLHzUihi4LCjegfoHFeqZcumCNwm1x" },
];

export function Ticker() {
  const row = [...EVENTS, ...EVENTS];
  return (
    <div className="z-ticker" aria-label="Real testnet transactions">
      <div className="z-track">
        {row.map((e, i) => (
          <a key={i} href={TX(e.h)} target="_blank" rel="noreferrer" className={`z-ev ${e.tone}`} aria-hidden={i >= EVENTS.length}>
            <i />
            {e.t}
            <code>{e.h.slice(0, 8)}…</code>
          </a>
        ))}
      </div>
    </div>
  );
}
