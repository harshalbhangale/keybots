import { useEffect } from "react";
import { Cards, HeroBar, NearMark, Try } from "./Sections";
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
          <div className="aurora" aria-hidden />
          <div className="hero-copy wrap">
            <h1 className="hero-title">
              <span>Type it.</span>
              <span>
                <NearMark /> <span className="lime">NEAR</span> does the rest.
              </span>
            </h1>
            <p className="hero-sub">The AI keyboard that pays, trades and stops scams, in any chat.</p>
            <HeroBar />
            <Downloads />
          </div>
        </section>

        <section className="section" id="try">
          <div className="wrap">
            <h2 className="sec-title center" data-reveal>
              Type in the chat. <span className="lime">Watch it on NEAR.</span>
            </h2>
            <Try />
          </div>
        </section>

        <section className="section tight">
          <div className="wrap">
            <Cards />
          </div>
        </section>

        <section className="finale" id="get">
          <div className="wrap">
            <div className="proof" data-reveal>
              <b>9/9</b>
              <span>
                end-to-end steps passed on NEAR testnet ·{" "}
                <a href={E2E} target="_blank" rel="noreferrer">
                  every transaction ↗
                </a>{" "}
                ·{" "}
                <a href={LEASH} target="_blank" rel="noreferrer">
                  the leash ↗
                </a>
              </span>
            </div>
            <h2 className="big-title" data-reveal>
              Your keys. <span className="lime">Your rules.</span>
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
