import { useEffect, useRef, useState, type ReactNode } from "react";
import { Ico } from "./Icons";

/**
 * The page's mascot: one iPhone with real Keybots screens. It sits beside the hero,
 * then stays on screen while the story scrolls past, switching screens as you go.
 */

type Shot = {
  src: string;
  alt: string;
  /** Zoom into part of the screen: x %, y %, scale. */
  focus?: [number, number, number];
  /** Draw the "Everything is stopped" state over the screen. */
  stop?: boolean;
};
type Net = "mainnet" | "testnet" | "both";
type Chapter = { id: string; icon: string; kicker: string; title: [string, string]; body: string; net: Net; shots: Shot[]; link?: [string, string] };

const S = (n: string) => `/screens/${n}.jpg`;
const MAIN_PAY = "https://nearblocks.io/txns/7hpf2Y28NJetvrAPtpP4oRbJjHEyUeboJAa1zk2xtds";
const MAIN_SCAM = "https://nearblocks.io/txns/9M4Xys3f6dmMxNFCdt3kQbgimRhnQWktNkr4RqhmaU6e";

const CHAPTERS: Chapter[] = [
  {
    id: "pay",
    icon: "pay",
    kicker: "Pay",
    title: ["Type it in any chat.", "Hold. Paid."],
    body: "Type “pay harshal 0.2”. The keyboard turns it into a payment and you hold to send. Spend Limits checks its rules on NEAR, then pays.",
    net: "both",
    shots: [
      { src: S("pay"), alt: "Keybots keyboard in Messages: Pay 0.2 NEAR to harshal, Hold to pay" },
      { src: S("activity"), alt: "Keybots Activity: Paid mom 0.5 NEAR", focus: [50, 30, 1.1] },
    ],
    link: ["A real payment on mainnet", MAIN_PAY],
  },
  {
    id: "scam",
    icon: "shield",
    kicker: "Scams",
    title: ["A scam gets pasted.", "Refused on chain."],
    body: "Text you copy goes to the Inbox Agent, which is never trusted. Spend Limits refuses the payment on NEAR and the account goes on your blocked list.",
    net: "both",
    shots: [
      { src: S("activity"), alt: "Keybots Activity: Blocked 2 NEAR to free-near-drop.testnet", focus: [50, 48, 1.12] },
      { src: S("blocklist"), alt: "Spend Limits: free-near-drop.testnet on the blocked list, known scam address", focus: [50, 82, 1.1] },
    ],
    link: ["A scam refused on mainnet", MAIN_SCAM],
  },
  {
    id: "trade",
    icon: "swap",
    kicker: "Trade a call",
    title: ["A call comes in.", "It swaps, inside the cap."],
    body: "Calls from traders you follow show up in the keyboard. Review one and hold: the Trading Agent swaps on Rhea, priced by NEAR Intents, never past its cap.",
    net: "testnet",
    shots: [
      { src: S("calls"), alt: "Keybots Calls: @CryptoKaleo SOL buy, Review trade" },
      { src: S("swap"), alt: "Keybots trade review: Hold to swap 0.2994 NEAR to USDC" },
      { src: S("swapped"), alt: "Keybots receipt: Swapped, decided by Spend Limits on NEAR" },
    ],
  },
  {
    id: "lanes",
    icon: "lock",
    kicker: "Lanes",
    title: ["Three lanes.", "Each with its own limits."],
    body: "Messages you copy, payments you type, and trades. Each lane has its own agent, its own key and its own caps. Only you change them, with Face ID.",
    net: "testnet",
    shots: [
      { src: S("lanes"), alt: "Spend Limits: lanes for messages you copy and payments, with limits" },
      { src: S("limits"), alt: "Spend Limits: each lane's limits per payment and per day" },
    ],
  },
  {
    id: "stop",
    icon: "stop",
    kicker: "Stop everything",
    title: ["One switch.", "Every agent stops."],
    body: "Pause every payment and trade at once. The contract enforces it, so even an agent that is already running gets refused.",
    net: "testnet",
    shots: [
      { src: S("lanes"), alt: "Spend Limits: Stop everything", focus: [50, 15, 1.14] },
      { src: S("lanes"), alt: "Everything is stopped", focus: [50, 15, 1.14], stop: true },
    ],
    link: ["The next payment, refused (testnet)", "https://testnet.nearblocks.io/txns/Hmk7LcjQJsjaqnZL9WAgS4DmVxY6PrxhN121boMY8nuR"],
  },
];

const HERO: Shot = { src: S("hero"), alt: "The Keybots keyboard on NEAR mainnet: three bots running, payments, messages you copy, trades" };
const NET_LABEL: Record<Net, string> = { mainnet: "Mainnet", testnet: "Testnet", both: "Mainnet + testnet" };

function IPhone({ shots, active, rot }: { shots: Shot[]; active: number; rot: number }) {
  return (
    <div className="iph" style={{ "--rot": rot } as React.CSSProperties}>
      <div className="iph-frame">
        <span className="iph-btn a" />
        <span className="iph-btn b" />
        <span className="iph-btn c" />
        <span className="iph-btn d" />
        <div className="iph-screen">
          {shots.map((s, i) => {
            const on = i === active;
            const [x, y, k] = s.focus ?? [50, 50, 1];
            return (
              <img
                key={i}
                src={s.src}
                alt={on ? s.alt : ""}
                aria-hidden={!on}
                className={`iph-shot ${on ? "on" : i < active ? "past" : ""}`}
                style={{ transformOrigin: `${x}% ${y}%`, "--k": on ? k : 1 } as React.CSSProperties}
                loading={i < 2 ? "eager" : "lazy"}
                decoding="async"
              />
            );
          })}
          <div className={`iph-stop ${shots[active]?.stop ? "on" : ""}`} aria-hidden={!shots[active]?.stop}>
            <div className="iph-stop-card">
              <span className="iph-stop-ico">
                <Ico n="stop" s={22} />
              </span>
              <b>Everything is stopped</b>
              <small>No agent can pay. Tap to let them work again.</small>
            </div>
          </div>
          <div className="iph-glass" />
        </div>
      </div>
    </div>
  );
}

export default function Journey({ hero }: { hero: ReactNode }) {
  const blocks = useRef<(HTMLElement | null)[]>([]);
  const [state, setState] = useState({ b: 0, t: 0 });

  // All screens in order: the hero's, then each chapter's. Map (block, t) to one of them.
  const all: Shot[] = [HERO, ...CHAPTERS.flatMap((c) => c.shots)];
  const start = [0];
  CHAPTERS.forEach((_, i) => start.push((i === 0 ? 1 : start[i] + CHAPTERS[i - 1].shots.length)));
  const shotFor = (b: number, t: number) => {
    if (b === 0) return 0;
    const c = CHAPTERS[b - 1];
    return start[b] + Math.min(c.shots.length - 1, Math.floor(t * c.shots.length * 1.15));
  };

  useEffect(() => {
    // Scroll events already arrive once per frame, so this runs straight from them.
    const on = () => {
      // Phones read a chapter as it enters at the bottom; wide screens at the middle.
      const mid = innerHeight * (innerWidth <= 900 ? 0.9 : 0.55);
      let b = 0;
      let t = 0;
      blocks.current.forEach((el, i) => {
        if (!el) return;
        const r = el.getBoundingClientRect();
        if (r.height > 0 && r.top <= mid) {
          b = i;
          t = Math.min(1, Math.max(0, (mid - r.top) / r.height));
        }
      });
      setState((s) => (s.b === b && Math.abs(s.t - t) < 0.01 ? s : { b, t }));
    };
    on();
    addEventListener("scroll", on, { passive: true });
    addEventListener("resize", on);
    return () => {
      removeEventListener("scroll", on);
      removeEventListener("resize", on);
    };
  }, []);

  const active = shotFor(state.b, state.t);
  // A slow turn as the story goes on: -10° at the hero to +10° at the end.
  const p = (state.b + state.t) / (CHAPTERS.length + 1);
  const rot = -10 + 20 * p;

  return (
    <>
    {/* On phones the hero text sits above the story; on wide screens it sits beside the iPhone. */}
    <div className="jr-mhero">{hero}</div>
    <section className="jr" id="how">
      <div className="jr-phone-col">
        <div className="jr-phone">
          <IPhone shots={all} active={active} rot={rot} />
        </div>
      </div>

      <div className="jr-text">
        <div className="jr-block jr-hero" ref={(el) => { blocks.current[0] = el; }}>
          {hero}
        </div>
        {CHAPTERS.map((c, i) => (
          <article key={c.id} className={`jr-block jr-ch ${state.b === i + 1 ? "on" : ""}`} ref={(el) => { blocks.current[i + 1] = el; }}>
            <div className="jr-card">
              <div className="jr-meta">
                <span className="jr-kick">
                  <Ico n={c.icon} s={15} /> {c.kicker}
                </span>
                <span className={`jr-net ${c.net}`}>{NET_LABEL[c.net]}</span>
              </div>
              <h2 className="jr-h">
                {c.title[0]} <span>{c.title[1]}</span>
              </h2>
              <p className="jr-p">{c.body}</p>
              {c.link && (
                <a className="jr-link" href={c.link[1]} target="_blank" rel="noreferrer">
                  {c.link[0]} ↗
                </a>
              )}
              <ol className="jr-dots" aria-hidden>
                {c.shots.map((_, k) => (
                  <li key={k} className={state.b === i + 1 && active === start[i + 1] + k ? "on" : ""} />
                ))}
              </ol>
            </div>
          </article>
        ))}
      </div>
    </section>
    </>
  );
}
