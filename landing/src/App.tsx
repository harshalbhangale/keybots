import { useEffect, useRef, useState } from "react";
import Phone, { SCENARIOS } from "./Phone";
import { Downloads, E2E, GitHub, LEASH, Mark, REPO } from "./ui";

function useReveal() {
  useEffect(() => {
    const io = new IntersectionObserver(
      (es) => es.forEach((e) => e.isIntersecting && (e.target.classList.add("in"), io.unobserve(e.target))),
      { rootMargin: "0px 0px -8% 0px" },
    );
    document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
}

/** The phone leans toward the pointer. */
function useLean<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || matchMedia("(pointer: coarse)").matches) return;
    const move = (e: PointerEvent) => {
      const x = e.clientX / innerWidth - 0.5;
      const y = e.clientY / innerHeight - 0.5;
      el.style.transform = `rotateY(${x * 10}deg) rotateX(${-y * 8}deg)`;
    };
    addEventListener("pointermove", move);
    return () => removeEventListener("pointermove", move);
  }, []);
  return ref;
}

const LEASH_FACTS = [
  ["Caps", "0.5 NEAR a payment, 1 a day, per agent"],
  ["Whose words", "What you paste goes to an agent that can't pay strangers"],
  ["Kill switch", "One switch stops every agent"],
];

export default function App() {
  useReveal();
  const [i, setI] = useState(0);
  const lean = useLean<HTMLDivElement>();
  const s = SCENARIOS[i];

  return (
    <>
      <nav className="nav">
        <a href="#top" className="brand">
          <Mark /> AIRKEY
        </a>
        <a className="nav-gh" href={REPO} target="_blank" rel="noreferrer">
          <GitHub size={16} /> GitHub
        </a>
      </nav>

      <main id="top">
        <section className="hero wrap">
          <div className="hero-copy">
            <span className="eyebrow">A keyboard, not an app</span>
            <h1>
              Pay, trade and stay safe <span className="lime">from the keyboard.</span>
            </h1>
            <p className="sub">
              Type “pay harshal 0.2” in any chat and hold. AI agents do it on NEAR, and a contract called the leash says no to
              anything you didn't allow.
            </p>
            <Downloads />
          </div>

          <div className="hero-phone">
            <div className="lean" ref={lean}>
              <Phone scenario={s} onDone={() => setI((x) => (x + 1) % SCENARIOS.length)} />
            </div>
            <div className="tabs" role="tablist" aria-label="Try a chat">
              {SCENARIOS.map((sc, k) => (
                <button key={sc.id} role="tab" aria-selected={k === i} className={k === i ? "on" : ""} onClick={() => setI(k)}>
                  {sc.tab}
                </button>
              ))}
            </div>
            <p className="tip">Hold the lime button, or let it play.</p>
          </div>
        </section>

        <section className="section wrap" id="what">
          <h2 data-reveal>Everything happens in the keyboard.</h2>
          <div className="rows">
            {SCENARIOS.map((sc, k) => (
              <button
                key={sc.id}
                className={`row ${k === i ? "on" : ""}`}
                data-reveal
                onClick={() => {
                  setI(k);
                  document.getElementById("top")?.scrollIntoView({ behavior: "smooth" });
                }}
              >
                <code>{sc.typed}</code>
                <span className="arrow">→</span>
                <span>{sc.shows}</span>
              </button>
            ))}
            <div className="row static" data-reveal>
              <code>100 usd to inr</code>
              <span className="arrow">→</span>
              <span>₹9,385.16 · Insert</span>
            </div>
            <div className="row static" data-reveal>
              <code>sell 1 near if it drops below 2</code>
              <span className="arrow">→</span>
              <span>Watched every 15 s, runs when the price crosses</span>
            </div>
          </div>
        </section>

        <section className="section wrap leash" id="leash">
          <div data-reveal>
            <h2>
              NEAR is <span className="lime">the leash.</span>
            </h2>
            <p className="sub">
              The keyboard never holds a key. Each agent's key can only ask a NEAR contract to pay, and the contract holds the
              money and checks your rules first.
            </p>
          </div>
          <div className="facts">
            {LEASH_FACTS.map(([b, t]) => (
              <div className="fact" key={b} data-reveal>
                <b>{b}</b>
                <span>{t}</span>
              </div>
            ))}
          </div>
          <div className="proof" data-reveal>
            <a href={E2E} target="_blank" rel="noreferrer">
              <b>9/9</b> end-to-end steps passed on testnet ↗
            </a>
            <a href={LEASH} target="_blank" rel="noreferrer">
              leash.airkey-harshal.testnet ↗
            </a>
          </div>
        </section>

        <section className="section wrap finale">
          <h2 data-reveal>
            Your AI. Your keys. <span className="lime">Your rules.</span>
          </h2>
          <div data-reveal>
            <Downloads />
          </div>
        </section>
      </main>

      <footer className="foot wrap">
        <span>
          <Mark size={18} /> AIRKEY · built at NEAR HACKATHON 2026 by Harshal Bhangale
        </span>
        <span>Testnet only · not financial advice</span>
      </footer>
    </>
  );
}
