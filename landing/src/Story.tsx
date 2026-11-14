import { useEffect, useRef, useState } from "react";
import Phone from "./Phone";
import { Ico } from "./Icons";
import { CHAIN, SCENARIOS } from "./scenarios";

/** One thing per scroll step: the phone plays it, the side shows what NEAR checked. */
const STEPS: { id: string; icon: string; tag: string }[] = [
  { id: "pay", icon: "pay", tag: "Pay" },
  { id: "scam", icon: "shield", tag: "Scams" },
  { id: "approve", icon: "face", tag: "Approve" },
  { id: "call", icon: "swap", tag: "Trade a call" },
  { id: "follow", icon: "follow", tag: "Follow" },
];
const PICK = STEPS.map((s) => SCENARIOS.find((c) => c.id === s.id)!);

export default function Story() {
  const sec = useRef<HTMLElement>(null);
  const [p, setP] = useState(0);
  const [replay, setReplay] = useState(0);
  const n = STEPS.length;

  useEffect(() => {
    let raf = 0;
    const on = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const el = sec.current;
        if (!el) return;
        const r = el.getBoundingClientRect();
        const total = r.height - innerHeight;
        setP(Math.min(1, Math.max(0, -r.top / total)));
      });
    };
    on();
    addEventListener("scroll", on, { passive: true });
    addEventListener("resize", on);
    return () => {
      cancelAnimationFrame(raf);
      removeEventListener("scroll", on);
      removeEventListener("resize", on);
    };
  }, []);

  const i = Math.min(n - 1, Math.floor(p * n));
  const local = p * n - i;
  const s = PICK[i];
  const chain = CHAIN[s.id] ?? [];

  const go = (k: number) => {
    const el = sec.current;
    if (!el) return;
    const top = el.getBoundingClientRect().top + scrollY;
    scrollTo({ top: top + ((k + 0.08) / n) * (el.offsetHeight - innerHeight), behavior: "smooth" });
  };

  return (
    <section className="st" ref={sec} id="how" style={{ height: `${n * 85 + 40}vh` }}>
      <div className="st-pin">
        <div className="y-wrap wide st-grid">
          <div className="st-side">
            <div className="st-rail" role="tablist" aria-label="Steps">
              {STEPS.map((x, k) => (
                <button key={x.id} role="tab" aria-selected={k === i} className={k === i ? "on" : k < i ? "past" : ""} onClick={() => go(k)}>
                  <span className="st-dot">
                    <Ico n={x.icon} s={15} />
                  </span>
                  <span className="st-tag">{x.tag}</span>
                  <i style={{ transform: `scaleX(${k < i ? 1 : k === i ? local : 0})` }} />
                </button>
              ))}
            </div>

            <div className="st-copy" key={s.id}>
              <span className="st-n">
                {String(i + 1).padStart(2, "0")} <small>/ {String(n).padStart(2, "0")}</small>
              </span>
              <h2 className="st-h">
                {s.headline[0]} <span className="grad">{s.headline[1]}</span>
              </h2>
              <ol className="st-chain">
                {chain.map(([t, k], m) => (
                  <li key={m} className={k} style={{ animationDelay: `${0.15 + m * 0.09}s` }}>
                    <i>{k === "ok" ? <Ico n="ok" s={12} /> : k === "fail" ? <Ico n="x" s={12} /> : "›"}</i>
                    {t}
                  </li>
                ))}
              </ol>
            </div>
          </div>

          <div className="st-phone" style={{ "--p": p } as React.CSSProperties}>
            <div className="st-tilt">
              <Phone key={s.id + replay} scenario={s} onDone={() => setReplay((r) => r + 1)} />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

/** What stays private, and how NEAR keeps it that way. */
const PRIV: { icon: string; title: string; text: string }[] = [
  { icon: "chip", title: "Private AI, in an enclave", text: "Rewrites and replies run on NEAR AI Cloud, inside secure hardware. Every answer carries its signature and the hardware's attestation, and both are checked." },
  { icon: "key", title: "Your key stays on your phone", text: "The owner key is made on the phone, kept in its Keychain and used only after Face ID. The server just passes on what the phone signed." },
  { icon: "lock", title: "Agents get small keys", text: "Each agent has its own NEAR account and a key that can only ask the Spend Limits contract to pay. It can't drain the wallet." },
  { icon: "eye-off", title: "Addresses, never secrets", text: "The vault keeps the addresses you paste often. Keys and seed phrases are never stored there." },
];

export function Private() {
  return (
    <div className="pv">
      <div className="pv-head" data-reveal>
        <span className="pv-badge">
          <Ico n="shield" s={15} /> Private by design
        </span>
        <h2 className="z-h2">
          It sees what you type. <span className="grad">It keeps it yours.</span>
        </h2>
      </div>
      <div className="pv-grid">
        {PRIV.map((x, k) => (
          <article className="pv-card" key={x.title} data-reveal style={{ transitionDelay: `${k * 70}ms` }}>
            <span className="pv-ico">
              <Ico n={x.icon} s={22} />
            </span>
            <b>{x.title}</b>
            <p>{x.text}</p>
          </article>
        ))}
      </div>
    </div>
  );
}
