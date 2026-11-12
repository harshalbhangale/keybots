import { useRef, useState } from "react";
import { useScrollProgress } from "../lib/hooks";

const clamp = (x: number) => Math.min(1, Math.max(0, x));
const ease = (t: number) => 1 - Math.pow(1 - t, 3);

/** The Leash screen, drawn for this page from what the app's Leash tab shows. */
function LeashScreen() {
  return (
    <div className="ui">
      <h4>Leash</h4>
      <div className="card killrow">
        <span>
          <b>Stop everything</b>
          <br />
          <span className="muted">Kill switch</span>
        </span>
        <span className="switch" style={{ background: "rgba(255,255,255,.14)" }} />
      </div>
      <div className="lbl">Waiting for you</div>
      <div className="card pend">
        <span className="dot" />
        <span style={{ flex: 1 }}>
          <b>0.3 NEAR to designer.near</b>
          <br />
          <span className="muted">R7 · new account, never paid</span>
        </span>
      </div>
      <div className="lbl">The leash holds</div>
      <div className="card">
        <div className="row">
          Balance <b>0.8323 NEAR</b>
        </div>
        <div className="row">
          Per payment <b>0.5 NEAR</b>
        </div>
        <div className="row">
          Per day <b>1 NEAR</b>
        </div>
      </div>
      <div className="lbl">Allowed · Blocked</div>
      <div className="card">
        <div className="row">
          friend.airkey-harshal… <b style={{ color: "var(--lime)" }}>allowed</b>
        </div>
        <div className="row">
          drain.airkey-harshal… <b style={{ color: "var(--red)" }}>blocked</b>
        </div>
      </div>
      <div className="face-id">Approve with Face ID</div>
    </div>
  );
}

const PHONES = [
  { key: "home", label: "Home", note: "What the leash holds, what needs you, today, recent. Screenshot from the simulator." },
  { key: "kb", label: "Keyboard", note: "Typed “pay harshal 1 for chai”. The leash blocked it (R4). Screenshot from the simulator." },
  { key: "leash", label: "Leash", note: "Kill switch, payments waiting, limits and lists. Every change is signed on the phone. Drawn for this page." },
];

export default function Phones() {
  const stage = useRef<HTMLDivElement>(null);
  const p = useScrollProgress(stage);
  const [front, setFront] = useState(1);
  const spread = ease(clamp((p - 0.12) / 0.32));
  const tilt = (p - 0.5) * 16;

  const place = (i: number) => {
    const slot = (i - front + 3) % 3; // 0 = front, 1 = right, 2 = left
    const side = slot === 0 ? 0 : slot === 1 ? 1 : -1;
    const x = side * 330 * spread;
    const z = slot === 0 ? 80 : -140 * spread;
    const ry = -side * 28 * spread + tilt * (slot === 0 ? 1 : 0.4);
    const rz = side * 3 * spread;
    return {
      transform: `translate3d(${x}px, ${slot === 0 ? 0 : 30 * spread}px, ${z}px) rotateY(${ry}deg) rotateZ(${rz}deg)`,
      zIndex: slot === 0 ? 3 : 1,
      filter: slot === 0 ? "none" : `brightness(${1 - 0.35 * spread})`,
    } as React.CSSProperties;
  };

  return (
    <section className="section" id="app" style={{ overflow: "hidden" }}>
      <div className="wrap">
        <div className="section-head center">
          <span className="eyebrow" data-reveal>
            The app and the keyboard
          </span>
          <h2 className="h-lg" data-reveal>
            Pay from any chat. <span className="muted">Approve with your face.</span>
          </h2>
          <p className="lede" data-reveal>
            An iOS keyboard that reads what you type, shows what it would do, and runs it. The app is the control panel, built
            with Liquid Glass. The keyboard never holds a key.
          </p>
        </div>

        <div className="phones-stage" ref={stage}>
          <div className="phones-rig">
            {PHONES.map((ph, i) => (
              <div className="phone" key={ph.key} style={place(i)} onClick={() => setFront(i)} role="button" aria-label={`Show ${ph.label}`}>
                <div className="screen">
                  <div className="island" />
                  {ph.key === "home" && <img src="/screens/home.png" alt="AIRKEY Home: what the leash holds, today's numbers and recent activity" loading="lazy" />}
                  {ph.key === "kb" && <img src="/screens/keyboard-blocked.png" alt="The AIRKEY keyboard showing a payment the leash blocked" loading="lazy" />}
                  {ph.key === "leash" && <LeashScreen />}
                </div>
              </div>
            ))}
          </div>
          <div className="phone-caption">
            <div className="phone-tabs" style={{ display: "flex", gap: 8 }}>
              {PHONES.map((ph, i) => (
                <button key={ph.key} className={front === i ? "active" : ""} onClick={() => setFront(i)}>
                  {ph.label}
                </button>
              ))}
            </div>
          </div>
        </div>
        <p className="muted" style={{ textAlign: "center", marginTop: 18, fontSize: 14 }}>
          {PHONES[front].note}
        </p>
      </div>
    </section>
  );
}
