import { lazy, Suspense, useRef } from "react";
import { useInView } from "../lib/hooks";
import { Arrow, GitHub, Mark, REPO } from "../ui";

const KeycapScene = lazy(() => import("../three/KeycapScene"));

export default function Closing() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, "200px");
  return (
    <>
      <section className="section" style={{ paddingBottom: 60 }}>
        <div className="wrap cta">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <span className="eyebrow" data-reveal>
              AIRKEY
            </span>
            <h2 className="h-lg" data-reveal>
              Your AI.
              <br />
              Your keys.
              <br />
              <span className="grad">Your rules.</span>
            </h2>
            <p className="lede" data-reveal>
              The contract, the server, the app and the keyboard are open source. Run the leash's tests without a chain, or the
              full flow on testnet.
            </p>
            <div className="hero-ctas" data-reveal style={{ justifyContent: "flex-start" }}>
              <a className="btn btn-lime" href={REPO} target="_blank" rel="noreferrer">
                <GitHub /> Read the code
              </a>
              <a className="btn btn-ghost" href={`${REPO}/blob/main/RULES.md`} target="_blank" rel="noreferrer">
                The rules <Arrow />
              </a>
            </div>
            <pre className="glass" data-reveal style={{ padding: "16px 20px", marginTop: 12, fontFamily: "var(--mono)", fontSize: 13, color: "var(--muted)", overflowX: "auto", borderRadius: 16 }}>
              <span className="lime">$</span> cd contracts/leash && cargo test{"\n"}
              <span className="lime">$</span> cd scripts && npm run e2e -- airkey-&lt;you&gt;.testnet
            </pre>
          </div>
          <div className="cta-canvas" ref={ref}>
            {inView && (
              <Suspense fallback={null}>
                <KeycapScene active={inView} />
              </Suspense>
            )}
            <span className="hint">press the key</span>
          </div>
        </div>
      </section>
      <footer className="foot">
        <div className="wrap">
          <span style={{ display: "inline-flex", alignItems: "center", gap: 10 }}>
            <Mark size={20} /> Built at NEAR HACKATHON 2026 by Harshal Bhangale · MIT
          </span>
          <span style={{ display: "inline-flex", gap: 18 }}>
            <a href="https://testnet.nearblocks.io/address/leash.airkey-harshal.testnet" target="_blank" rel="noreferrer">
              Leash on testnet
            </a>
            <a href={REPO} target="_blank" rel="noreferrer">
              GitHub
            </a>
          </span>
        </div>
      </footer>
    </>
  );
}
