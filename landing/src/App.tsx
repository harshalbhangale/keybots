import { useEffect } from "react";
import { Backdrop, Callers, Features, Stickers, Try, WORKS } from "./Sections";
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

export default function App() {
  useReveal();
  return (
    <>
      <nav className="nav">
        <a href="#top" className="brand">
          <Mark /> AIRKEY
        </a>
        <span className="nav-end">
          <a className="nav-link" href={REPO} target="_blank" rel="noreferrer">
            <GitHub size={16} /> GitHub
          </a>
          <a className="nav-cta" href="#get">
            Get AIRKEY
          </a>
        </span>
      </nav>

      <main id="top">
        <section className="hero">
          <Backdrop />
          <div className="hero-copy wrap">
            <h1 className="hero-title">
              <span>Type it.</span> <span className="lime">NEAR does it.</span>
            </h1>
            <p className="hero-sub">The AI keyboard that pays, trades and says no to scams.</p>
            <Downloads />
          </div>
        </section>

        <section className="section features" id="features">
          <div className="wrap">
            <Stickers>
              <h2 className="big-title">
                <span>One keyboard.</span> <span>Everything on NEAR.</span>
              </h2>
            </Stickers>
            <Features />
          </div>
        </section>

        <section className="section kol" id="follow">
          <div className="wrap">
            <div className="kol-head" data-reveal>
              <span className="pill-soon">Soon</span>
              <h2 className="sec-title">
                Follow the callers <span className="lime">who are right.</span>
              </h2>
              <p className="sec-sub">Every call scored on NEAR. Copy the good ones, inside your caps.</p>
            </div>
            <Callers />
          </div>
        </section>

        <section className="works wrap" data-reveal>
          <h3>Works with</h3>
          <ul>
            {WORKS.map((w) => (
              <li key={w}>{w}</li>
            ))}
          </ul>
        </section>

        <section className="section" id="try">
          <div className="wrap">
            <div className="try-cue" data-reveal>
              <p>Try it here.</p>
            </div>
            <Try />
          </div>
        </section>

        <section className="section proof wrap" data-reveal>
          <div className="proof-num">
            <b>9/9</b>
            <span>
              end-to-end steps passed
              <br />
              on NEAR testnet
            </span>
          </div>
          <div className="proof-links">
            <a href={E2E} target="_blank" rel="noreferrer">See every transaction ↗</a>
            <a href={LEASH} target="_blank" rel="noreferrer">leash.airkey-harshal.testnet ↗</a>
            <a href={REPO} target="_blank" rel="noreferrer">Open source on GitHub ↗</a>
          </div>
        </section>

        <section className="finale" id="get">
          <div className="wrap">
            <h2 className="big-title" data-reveal>
              <span>Your keys.</span> <span className="lime">Your rules.</span>
            </h2>
            <div data-reveal>
              <Downloads />
            </div>
          </div>
        </section>
      </main>

      <footer className="foot wrap">
        <span>
          <Mark size={18} /> © 2026 AIRKEY · built at NEAR HACKATHON by Harshal Bhangale
        </span>
        <span>Testnet only · not financial advice</span>
      </footer>
    </>
  );
}
