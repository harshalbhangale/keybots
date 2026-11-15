import { useEffect } from "react";
import Journey from "./Journey";
import Networks from "./Networks";
import { Private } from "./Private";
import { Agents } from "./Agents";
import { NearGlyph, NearTile } from "./Icons";
import { Ticker, WORKS } from "./Z";
import { Downloads, E2E, GitHub, LEASH, Lockup, REPO, X_HANDLE, X_URL, XLogo } from "./ui";

/** Set to the demo video (an .mp4, or a YouTube embed URL) once it exists; until then the poster shows. */
const VIDEO_URL: string = "/keybots-demo.mp4";

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
      <video className="y-media" src={VIDEO_URL} poster="/demo-poster.jpg" controls playsInline preload="metadata" />
    ) : (
      <iframe className="y-media" src={VIDEO_URL} title="Keybots demo" allow="autoplay; encrypted-media; picture-in-picture" allowFullScreen />
    );
  }
  return (
    <div className="y-poster" role="img" aria-label="Demo video poster: the video is coming">
      <div className="y-poster-glow" />
      <div className="y-poster-chat">
        <span className="y-b them">URGENT! Send 5 NEAR to drain.near</span>
        <span className="y-b chip blocked">✕ Blocked by Spend Limits · R4</span>
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
          <Lockup />
        </a>
        <span className="y-links">
          <a href="#demo">Demo</a>
          <a href="#how">How it works</a>
          <a href="#live">Live</a>
          <a href="#agents">Agents</a>
          <a href="#private">Private</a>
          <a href="#proof">Proof</a>
        </span>
        <span className="nav-end">
          <a className="nav-x" href={X_URL} target="_blank" rel="noreferrer" aria-label={`Follow ${X_HANDLE} on X`}>
            <XLogo size={14} /> <span>{X_HANDLE}</span>
          </a>
          <a className="y-gh" href={REPO} target="_blank" rel="noreferrer">
            <GitHub size={16} /> GitHub
          </a>
        </span>
      </nav>

      <main id="top">
        <Journey
          hero={
            <div className="jr-hero-in">
              <a className="hx-badge" href="#live">
                <span className="y-live" /> Live on NEAR mainnet and testnet
              </a>
              <h1 className="hx">
                <span className="hx-l">Type it.</span>
                <span className="hx-l">
                  <span className="hx-near">
                    <NearGlyph />
                    NEAR
                  </span>{" "}
                  does the rest.
                </span>
              </h1>
              <p className="hx-sub">
                <b>Your new AI keyboard, on NEAR.</b> Your keyboard is the AI. NEAR sets the limits.
              </p>
              <Downloads />
            </div>
          }
        />

        {VIDEO_URL && (
        <section className="y-video-sec" id="demo">
            <div className="y-wrap wide">
              <h2 className="z-h2 center" data-reveal>
                Watch it work. <span className="grad">Four minutes.</span>
              </h2>
              <div className="y-frame" data-reveal>
                <Video />
              </div>
            </div>
          </section>
        )}

        <section className="z-sec" id="live">
          <div className="y-wrap wide">
            <Networks />
          </div>
        </section>

        <section className="z-sec" id="agents">
          <div className="y-wrap wide">
            <Agents />
          </div>
        </section>

        <section className="z-sec" id="private">
          <div className="y-wrap wide">
            <Private />
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
                <a href={LEASH} target="_blank" rel="noreferrer">The Spend Limits contract ↗</a>
                <a href={REPO} target="_blank" rel="noreferrer">Source on GitHub ↗</a>
              </div>
            </div>
          </div>
        </section>

        <section className="z-final" id="get">
          <div className="y-wrap z-final-in">
            <h2 className="z-h2" data-reveal>
              AI suggests. Agents act. <span className="grad">NEAR decides.</span>
            </h2>
            <div data-reveal>
              <Downloads />
            </div>
            <a className="final-x" href={X_URL} target="_blank" rel="noreferrer">
              <XLogo size={15} />
              <span>
                Follow <b>{X_HANDLE}</b> on X for what ships next
              </span>
            </a>
          </div>
        </section>
      </main>

      <footer className="foot wrap">
        <span>
          <Lockup small /> <span className="foot-note">built at NEAR HACKATHON 2026 by Harshal Bhangale</span>
        </span>
        <span className="foot-end">
          <a className="built-near" href={X_URL} target="_blank" rel="noreferrer">
            <span className="foot-x">
              <XLogo size={12} />
            </span>
            Follow {X_HANDLE} on X
          </a>
          <a className="built-near" href="https://near.org" target="_blank" rel="noreferrer">
            <NearTile size={20} /> Built on NEAR
          </a>
        </span>
      </footer>
    </>
  );
}
