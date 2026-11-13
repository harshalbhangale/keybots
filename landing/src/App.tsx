import { useEffect } from "react";
import { Cards, HeroBar, NearMark, Try } from "./Sections";
import { BuiltOnNear, Proof, Rules, TryYourself } from "./More";
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
          <a className="nav-link" href="#proof">
            Proof
          </a>
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
            <p className="hero-sub">Your keyboard is the AI. NEAR is the leash.</p>
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

        <section className="section tight" id="leash">
          <div className="wrap">
            <h2 className="sec-title center" data-reveal>
              How the leash <span className="lime">says no.</span>
            </h2>
            <p className="sec-sub center" data-reveal>
              Each agent's key can only ask a NEAR contract to pay. The contract holds the money and checks five things first.
            </p>
            <Rules />
            <Cards />
          </div>
        </section>

        <section className="section tight" id="proof">
          <div className="wrap">
            <h2 className="sec-title center" data-reveal>
              Don't trust the page. <span className="lime">Read the chain.</span>
            </h2>
            <Proof e2e={E2E} leash={LEASH} />
          </div>
        </section>

        <section className="section tight" id="yourself">
          <div className="wrap">
            <h2 className="sec-title center" data-reveal>
              Try it yourself.
            </h2>
            <TryYourself repo={REPO} />
          </div>
        </section>

        <section className="finale" id="get">
          <div className="wrap">
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
        <span className="foot-end">
          <BuiltOnNear />
          <span>Testnet only · not financial advice</span>
        </span>
      </footer>
    </>
  );
}
