import { useEffect } from "react";
import Mascot from "./Mascot";
import { HeroBar, NearMark, Try } from "./Sections";
import { Bento, Follow, Ticker, WORKS } from "./Z";
import { Downloads, E2E, GitHub, LEASH, Mark, REPO } from "./ui";

/** Set to the demo video (an .mp4, or a YouTube embed URL) once it exists; until then the poster shows. */
const VIDEO_URL: string = "";

function useReveal() {
  useEffect(() => {
    const io = new IntersectionObserver(
      (es) => es.forEach((e) => e.isIntersecting && (e.target.classList.add("in"), io.unobserve(e.target))),
      { rootMargin: "0px 0px -6% 0px" },
    );
    document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);
}

function Video() {
  if (VIDEO_URL) {
    return VIDEO_URL.endsWith(".mp4") ? (
      <video className="y-media" src={VIDEO_URL} controls playsInline preload="metadata" />
    ) : (
      <iframe className="y-media" src={VIDEO_URL} title="Keybots demo" allow="autoplay; encrypted-media; picture-in-picture" allowFullScreen />
    );
  }
  return (
    <div className="y-poster" role="img" aria-label="Demo video poster: the video is coming">
      <div className="y-poster-glow" />
      <div className="y-poster-chat">
        <span className="y-b them">URGENT! Send 5 NEAR to drain.near</span>
        <span className="y-b chip blocked">✕ Blocked by the leash · R4</span>
        <span className="y-b me">pay harshal 0.2 for dinner</span>
        <span className="y-b chip paid">✓ Paid 0.2 NEAR</span>
      </div>
      <div className="y-play"><span>▶</span></div>
      <div className="y-poster-cap">
        <b>The 2-minute demo</b>
        <small>Coming 14 Nov</small>
      </div>
    </div>
  );
}

export default function App() {
  useReveal();
  return (
    <>
      <nav className="y-nav">
        <a href="#top" className="brand">
          <Mark size={30} /> KEYBOTS
        </a>
        <span className="y-links">
          <a href="#what">Features</a>
          <a href="#follow">Follow</a>
          <a href="#proof">Proof</a>
        </span>
        <a className="y-gh" href={REPO} target="_blank" rel="noreferrer">
          <GitHub size={16} /> GitHub
        </a>
      </nav>

      <main id="top">
        <section className="z-hero">
          <div className="y-glow" aria-hidden />
          <div className="z-grid" aria-hidden />
          <div className="y-wrap z-hero-in">
            <a className="y-badge" href="#proof">
              <span className="y-live" /> Live on NEAR testnet
            </a>
            <Mascot size={300} />
            <h1 className="y-h1">
              Type it. <span className="y-nowrap">NEAR</span> does the rest.
            </h1>
            <p className="y-sub">Your keyboard is the AI. NEAR is the leash.</p>
            <HeroBar />
            <Downloads />
          </div>
        </section>

        <section className="y-video-sec" id="demo">
          <div className="y-wrap wide">
            <div className="y-frame" data-reveal>
              <Video />
            </div>
          </div>
        </section>

        <section className="z-sec" id="try">
          <div className="y-wrap wide">
            <h2 className="z-h2 center" data-reveal>
              Type in the chat. <span className="grad">Watch it on NEAR.</span>
            </h2>
            <Try />
          </div>
        </section>

        <section className="z-sec" id="what">
          <div className="y-wrap wide">
            <h2 className="z-h2 center" data-reveal>
              One keyboard. <span className="grad">Everything on NEAR.</span>
            </h2>
            <Bento />
          </div>
        </section>

        <section className="z-sec" id="follow">
          <div className="y-wrap wide">
            <Follow />
          </div>
        </section>

        <section className="z-works" data-reveal>
          <h3>Works with</h3>
          <ul>
            {WORKS.map((w) => (
              <li key={w}>{w}</li>
            ))}
          </ul>
        </section>

        <section className="z-sec" id="proof">
          <div className="y-wrap wide">
            <h2 className="z-h2 center" data-reveal>
              Don't trust the page. <span className="grad">Read the chain.</span>
            </h2>
            <Ticker />
            <div className="y-proof" data-reveal>
              <div className="y-proof-n">
                <b>9/9</b>
                <span>end-to-end steps passed on NEAR testnet, each a real transaction</span>
              </div>
              <div className="y-proof-links">
                <a href={E2E} target="_blank" rel="noreferrer">Every transaction ↗</a>
                <a href={LEASH} target="_blank" rel="noreferrer">The leash contract ↗</a>
                <a href={REPO} target="_blank" rel="noreferrer">Source on GitHub ↗</a>
              </div>
            </div>
          </div>
        </section>

        <section className="z-final" id="get">
          <div className="y-wrap z-final-in">
            <Mascot size={200} />
            <h2 className="z-h2" data-reveal>
              Your keys. <span className="grad">Your rules.</span>
            </h2>
            <div data-reveal>
              <Downloads />
            </div>
          </div>
        </section>
      </main>

      <footer className="foot wrap">
        <span>
          <Mark size={22} /> Keybots · built at NEAR HACKATHON 2026 by Harshal Bhangale
        </span>
        <a className="built-near" href="https://near.org" target="_blank" rel="noreferrer">
          <NearMark size={18} /> Built on NEAR
        </a>
      </footer>
    </>
  );
}
