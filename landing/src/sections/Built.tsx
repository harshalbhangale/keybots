import { useEffect, useRef, useState } from "react";
import { useInView } from "../lib/hooks";

type NodeId = "kb" | "app" | "key" | "srv" | "checks" | "ai" | "pay" | "inbox" | "leash" | "recv" | "events";

const W = 150;
const H = 46;
const NODES: Record<NodeId, { x: number; y: number; label: string; sub: string }> = {
  kb: { x: 10, y: 40, label: "AIRKEY keyboard", sub: "iOS extension" },
  app: { x: 10, y: 170, label: "AIRKEY app", sub: "SwiftUI, Liquid Glass" },
  key: { x: 10, y: 300, label: "Device key", sub: "Keychain + Face ID" },
  srv: { x: 205, y: 40, label: "Server", sub: "POST /v1/command" },
  checks: { x: 205, y: 170, label: "Receiver checks", sub: "age, lists, paid before" },
  ai: { x: 205, y: 300, label: "NEAR AI Cloud", sub: "only if rules can't read it" },
  pay: { x: 400, y: 95, label: "Pay Agent", sub: "trusted · fn-call key" },
  inbox: { x: 400, y: 245, label: "Inbox Agent", sub: "untrusted · fn-call key" },
  leash: { x: 595, y: 170, label: "Leash contract", sub: "Rust on NEAR testnet" },
  recv: { x: 595, y: 40, label: "Receiver", sub: "harshal.near" },
  events: { x: 595, y: 300, label: "On-chain events", sub: "NEP-297 · airkey" },
};

type Step = { text: string; from: NodeId; to: NodeId; detail: string };
const JOURNEYS: { name: string; steps: Step[] }[] = [
  {
    name: "Pay from the keyboard",
    steps: [
      { from: "kb", to: "srv", text: "You type “pay harshal 0.2 for dinner” and tap Run", detail: "The keyboard sends the text with source: typed. It holds no key." },
      { from: "srv", to: "srv", text: "The server reads it with rules first", detail: "No AI needed for a plain payment. The parser finds receiver, amount and memo." },
      { from: "srv", to: "checks", text: "It checks the receiver", detail: "Exists, blocklisted, allowlisted, account age, contract code, paid before." },
      { from: "checks", to: "pay", text: "Typed words go to the trusted Pay Agent", detail: "The tier belongs to the agent, never to the request." },
      { from: "pay", to: "leash", text: "The agent asks the leash: pay()", detail: "Its function-call key can only call pay and report." },
      { from: "leash", to: "recv", text: "R1 to R7 and R0 pass: the leash sends 0.2 NEAR", detail: "The contract holds the money and sends it itself." },
      { from: "leash", to: "events", text: "It logs a paid event", detail: "A NEP-297 event anyone can read from the chain." },
      { from: "srv", to: "kb", text: "A lime chip with the receipt", detail: "Share puts the receipt in the chat you're typing in." },
    ],
  },
  {
    name: "Paste a scam",
    steps: [
      { from: "kb", to: "srv", text: "You copy a message and tap Check copied", detail: "Pasted text is sent with source: pasted." },
      { from: "srv", to: "inbox", text: "Someone else's words go to the untrusted Inbox Agent", detail: "A fooled AI can't promote itself to the trusted tier." },
      { from: "inbox", to: "leash", text: "“Send 5 NEAR to drain.near” reaches the leash", detail: "The agent asks; the leash decides." },
      { from: "leash", to: "events", text: "R4: over the 0.5 NEAR per-payment cap. Blocked", detail: "The blocked decision is an on-chain event." },
      { from: "inbox", to: "leash", text: "The agent reports drain.near", detail: "report() puts it on the blocklist at once (R3 for everyone after)." },
      { from: "srv", to: "kb", text: "A red chip: blocked by the leash", detail: "Nothing moved. The receipt says which rule fired." },
    ],
  },
  {
    name: "Approve with Face ID",
    steps: [
      { from: "kb", to: "srv", text: "You type “pay designer 0.3 for the logo”", detail: "Your own words, so the trusted agent." },
      { from: "srv", to: "checks", text: "The check warns: new account, never paid", detail: "A warning can only make the agent stricter." },
      { from: "pay", to: "leash", text: "The agent calls pay with ask_owner: true", detail: "R7 fires: a pending payment, recorded on chain." },
      { from: "leash", to: "app", text: "It shows up in the app, waiting for you", detail: "Home and Leash both show payments that need you." },
      { from: "app", to: "key", text: "Approve: Face ID unlocks this device's key", detail: "The server built the transaction; the phone signs it." },
      { from: "key", to: "leash", text: "The server relays it; the leash re-checks and pays", detail: "R1 and R3 run again. The amount counts toward today's cap." },
    ],
  },
];

const anchor = (id: NodeId, toward: NodeId) => {
  const a = NODES[id];
  const b = NODES[toward];
  const cx = a.x + W / 2;
  const cy = a.y + H / 2;
  if (Math.abs(b.x - a.x) > 40) return { x: b.x > a.x ? a.x + W : a.x, y: cy };
  return { x: cx, y: b.y > a.y ? a.y + H : a.y };
};

export default function Built() {
  const [j, setJ] = useState(0);
  const [i, setI] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, "-15%");
  const [paused, setPaused] = useState(false);
  const steps = JOURNEYS[j].steps;
  const step = steps[i];

  useEffect(() => {
    if (!inView || paused) return;
    const id = setTimeout(() => setI((x) => (x + 1) % steps.length), 2300);
    return () => clearTimeout(id);
  }, [inView, paused, i, steps.length]);

  const active = new Set<NodeId>([step.from, step.to]);
  const used = new Set<NodeId>(steps.flatMap((s) => [s.from, s.to]));
  const edges = steps
    .map((s, k) => ({ ...s, k }))
    .filter((s) => s.from !== s.to)
    .filter((s, k, arr) => arr.findIndex((o) => o.from === s.from && o.to === s.to) === k);

  return (
    <section className="section" id="built">
      <div className="wrap">
        <div className="section-head center">
          <span className="eyebrow" data-reveal>
            How it's built
          </span>
          <h2 className="h-lg" data-reveal>
            Follow a payment through the system.
          </h2>
          <p className="lede" data-reveal>
            A keyboard and an app on the phone, a thin server that reads and checks, two agents with restricted keys, and the
            contract that decides. Pick a journey, or click a step.
          </p>
        </div>

        <div className="flow glass" ref={ref} data-reveal onMouseEnter={() => setPaused(true)} onMouseLeave={() => setPaused(false)}>
          <div>
            <div className="flow-tabs">
              {JOURNEYS.map((jr, k) => (
                <button
                  key={jr.name}
                  className={k === j ? "active" : ""}
                  onClick={() => {
                    setJ(k);
                    setI(0);
                  }}
                >
                  {jr.name}
                </button>
              ))}
            </div>
            <svg viewBox="0 0 755 360" role="img" aria-label={`Diagram: ${JOURNEYS[j].name}`}>
              <defs>
                <marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M0 0 10 5 0 10z" fill="#c6f25a" />
                </marker>
                <marker id="ahd" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                  <path d="M0 0 10 5 0 10z" fill="#3a3d3a" />
                </marker>
              </defs>
              {["You", "Server", "Agents", "NEAR"].map((c, k) => (
                <text key={c} x={[85, 280, 475, 670][k]} y={22} textAnchor="middle" fill="#5b5d58" fontSize="11" fontFamily="JetBrains Mono, monospace">
                  {c.toUpperCase()}
                </text>
              ))}
              {edges.map((e) => {
                const a = anchor(e.from, e.to);
                const b = anchor(e.to, e.from);
                const on = e.from === step.from && e.to === step.to;
                const mx = (a.x + b.x) / 2;
                const d = Math.abs(a.y - b.y) < 2 || Math.abs(a.x - b.x) < 2 ? `M${a.x} ${a.y} L${b.x} ${b.y}` : `M${a.x} ${a.y} C${mx} ${a.y} ${mx} ${b.y} ${b.x} ${b.y}`;
                return (
                  <path
                    key={`${e.from}-${e.to}`}
                    d={d}
                    fill="none"
                    stroke={on ? "#c6f25a" : "#2c2f2c"}
                    strokeWidth={on ? 2.2 : 1.4}
                    strokeDasharray={on ? "6 6" : undefined}
                    markerEnd={on ? "url(#ah)" : "url(#ahd)"}
                    style={on ? { animation: "dash 0.9s linear infinite", filter: "drop-shadow(0 0 6px rgba(198,242,90,.6))" } : undefined}
                  />
                );
              })}
              {(Object.keys(NODES) as NodeId[]).map((id) => {
                const n = NODES[id];
                const on = active.has(id);
                const inJourney = used.has(id);
                return (
                  <g key={id} transform={`translate(${n.x} ${n.y})`} opacity={inJourney ? 1 : 0.28} style={{ transition: "opacity .3s" }}>
                    <rect
                      width={W}
                      height={H}
                      rx={12}
                      fill={on ? "#c6f25a" : "#151817"}
                      stroke={on ? "#c6f25a" : "#2c2f2c"}
                      style={{ transition: "fill .25s, stroke .25s", filter: on ? "drop-shadow(0 0 14px rgba(198,242,90,.45))" : undefined }}
                    />
                    <text x={W / 2} y={20} textAnchor="middle" fontSize="13" fontWeight={600} fill={on ? "#0b0c0a" : "#f2f0ea"} fontFamily="Inter Tight, sans-serif">
                      {n.label}
                    </text>
                    <text x={W / 2} y={35} textAnchor="middle" fontSize="10" fill={on ? "#2b3313" : "#8d8f89"} fontFamily="JetBrains Mono, monospace">
                      {n.sub}
                    </text>
                  </g>
                );
              })}
            </svg>
          </div>
          <div>
            <div className="flow-steps">
              {steps.map((s, k) => (
                <button key={k} className={k === i ? "active" : k < i ? "done" : ""} onClick={() => setI(k)}>
                  <span>{k + 1}</span>
                  {s.text}
                </button>
              ))}
            </div>
            <div className="flow-detail">
              <b>
                {NODES[step.from].label}
                {step.from !== step.to && ` → ${NODES[step.to].label}`}
              </b>
              {step.detail}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
