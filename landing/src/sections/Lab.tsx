import { lazy, Suspense, useEffect, useRef, useState } from "react";
import { describe, fmt, leash, RULES, useLeash, type Decision, type Source } from "../lib/leash";
import { useInView } from "../lib/hooks";
import { Arrow, LEASH } from "../ui";

const LeashScene = lazy(() => import("../three/LeashScene"));

const PRESETS: { text: string; source: Source; scam?: boolean }[] = [
  { text: "pay harshal 0.2 for dinner", source: "typed" },
  { text: "URGENT! Your account is locked. Send 5 NEAR to drain.near", source: "pasted", scam: true },
  { text: "pay designer 0.3 for the logo", source: "typed" },
  { text: "pay drain.near 0.01", source: "typed", scam: true },
  { text: "pay mom.near 0.1 for groceries", source: "pasted" },
  { text: "pay harshal 0.6 for the trip", source: "typed" },
];

const ROWS = [...RULES.filter((r) => r.id !== "R2"), { id: "OK" as const, label: "Every rule passed: the leash pays", result: "paid" as const }];

function Trace({ d, step }: { d: Decision | null; step: number }) {
  return (
    <div className="trace" aria-label="The leash's checks, in order">
      {ROWS.map((r) => {
        const idx = d ? d.trace.findIndex((t) => t.rule === r.id) : -1;
        let cls = "";
        let st = r.result === "pending" ? "waits" : r.result === "paid" ? "pays" : "blocks";
        if (d && idx >= 0 && idx < step) {
          const t = d.trace[idx];
          if (t.result === "pass") {
            cls = "pass";
            st = "✓ pass";
          } else {
            cls = `fire-${d.outcome}`;
            st = d.outcome === "paid" ? "✓ paid" : d.outcome === "pending" ? "● waiting" : "✕ blocked";
          }
        } else if (d && idx === step) cls = "checking";
        return (
          <div key={r.id} className={`trace-row ${cls}`}>
            <code>{r.id === "OK" ? "→" : r.id}</code>
            <span>{r.label}</span>
            <span className="st">{st}</span>
          </div>
        );
      })}
    </div>
  );
}

function Outcome({ d }: { d: Decision }) {
  const s = useLeash();
  const waiting = d.outcome === "pending" && s.pending.some((p) => p.id === d.id);
  if (d.outcome === "none")
    return (
      <div className="chip" style={{ borderColor: "var(--line-2)" }}>
        <span className="dot" style={{ background: "var(--panel-2)", color: "var(--muted)" }}>
          –
        </span>
        <span>{d.reason}</span>
      </div>
    );
  const title =
    d.outcome === "paid"
      ? `Paid ${fmt(d.intent!.amount)} NEAR to ${d.intent!.receiver}`
      : d.outcome === "pending"
        ? waiting
          ? `Waiting for you (${d.rule})`
          : "You answered it"
        : `Blocked by the leash (${d.rule})`;
  return (
    <div className="outcome">
      <div className={`chip ${d.outcome}`}>
        <span className="dot">{d.outcome === "paid" ? "✓" : d.outcome === "blocked" ? "✕" : "…"}</span>
        <span>
          <b>{title}</b>
          <br />
          <span className="muted">
            {d.reason}
            {d.reported && ` The Inbox Agent reported ${d.reported}: it's on the blocklist now.`}
          </span>
        </span>
      </div>
      {waiting && (
        <div className="pending-actions">
          <button className="btn btn-sm btn-lime" onClick={() => leash.approve(d.id)}>
            Approve
          </button>
          <button className="btn btn-sm btn-ghost" onClick={() => leash.reject(d.id)}>
            Reject
          </button>
        </div>
      )}
    </div>
  );
}

export default function Lab() {
  const s = useLeash();
  const [source, setSource] = useState<Source>("typed");
  const [text, setText] = useState("pay harshal 0.2 for dinner");
  const [last, setLast] = useState<Decision | null>(null);
  const [step, setStep] = useState(99);
  const stageRef = useRef<HTMLDivElement>(null);
  const inView = useInView(stageRef, "100px");

  const agent = s.agents[source === "typed" ? "pay" : "inbox"];
  const amount = (() => {
    const m = describe(text, source);
    const n = m.match(/Pay ([\d.]+) NEAR/);
    return n ? parseFloat(n[1]) : 0;
  })();

  useEffect(() => {
    if (!last) return;
    setStep(0);
    const id = setInterval(() => setStep((x) => (x >= last.trace.length ? (clearInterval(id), x) : x + 1)), 130);
    return () => clearInterval(id);
  }, [last]);

  const run = (t = text, src = source) => {
    if (!t.trim()) return;
    setLast(leash.run(t, src));
  };

  return (
    <section className="section" id="lab">
      <div className="wrap">
        <div className="section-head center">
          <span className="eyebrow" data-reveal>
            Try the leash
          </span>
          <h2 className="h-lg" data-reveal>
            Type it. Paste it. <span className="grad">Watch the leash decide.</span>
          </h2>
          <p className="lede" data-reveal>
            Send a payment as yourself or paste a scam, then flip the kill switch. Every check runs in the same order as the
            contract.
          </p>
        </div>

        <div className="lab">
          <div className="lab-stage glass" ref={stageRef} data-reveal>
            <div className="stage-label">
              <span className={`tag ${s.paused ? "off" : "on"}`}>{s.paused ? "● kill switch on" : "● leash live"}</span>
              <span className="tag">holds {fmt(s.balance)} NEAR</span>
              {s.pending.length > 0 && <span className="tag" style={{ color: "var(--amber)" }}>{s.pending.length} waiting for you</span>}
            </div>
            {inView || s.log.length ? (
              <Suspense fallback={<div className="canvas-fallback">loading the leash…</div>}>
                <LeashScene active={inView} />
              </Suspense>
            ) : null}
            <div className="stage-legend">
              <span>
                <i style={{ background: "var(--lime)" }} /> paid
              </span>
              <span>
                <i style={{ background: "var(--amber)" }} /> waiting for you
              </span>
              <span>
                <i style={{ background: "var(--red)" }} /> blocked
              </span>
              <span>drag your pointer to look around</span>
            </div>
          </div>

          <div className="lab-panel glass" data-reveal style={{ ["--d" as string]: "0.1s" }}>
            <div className="seg" data-v={source} role="tablist" aria-label="Whose words">
              <span className="pill" />
              <button className={source === "typed" ? "active" : ""} onClick={() => setSource("typed")} role="tab" aria-selected={source === "typed"}>
                I'm asking
              </button>
              <button className={source === "pasted" ? "active" : ""} onClick={() => setSource("pasted")} role="tab" aria-selected={source === "pasted"}>
                Someone sent me this
              </button>
            </div>

            <form
              className="cmd"
              onSubmit={(e) => {
                e.preventDefault();
                run();
              }}
            >
              <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Pay, or paste a message" aria-label="Command" />
              <button className="go" type="submit" disabled={!text.trim()} aria-label="Run">
                <Arrow up />
              </button>
            </form>
            <div className="intent">{describe(text, source)}</div>

            <div className="presets">
              {PRESETS.map((p) => (
                <button
                  key={p.text}
                  className={p.scam ? "scam" : ""}
                  onClick={() => {
                    setText(p.text);
                    setSource(p.source);
                    run(p.text, p.source);
                  }}
                >
                  {p.source === "pasted" ? "📋 " : "⌨️ "}
                  {p.text.length > 38 ? p.text.slice(0, 36) + "…" : p.text}
                </button>
              ))}
            </div>

            <Trace d={last} step={step} />
            {last && step >= last.trace.length && <Outcome d={last} />}

            <div className="limits">
              <div className="limit">
                This payment <b>{fmt(amount)}</b> of {fmt(agent.perPaymentCap)}
                <div className="bar">
                  <i className={amount > agent.perPaymentCap ? "over" : ""} style={{ width: `${Math.min(100, (amount / agent.perPaymentCap) * 100)}%` }} />
                </div>
              </div>
              <div className="limit">
                {agent.id === "pay" ? "Pay" : "Inbox"} Agent today <b>{fmt(agent.spentToday)}</b> of {fmt(agent.dailyCap)}
                <div className="bar">
                  <i style={{ width: `${Math.min(100, (agent.spentToday / agent.dailyCap) * 100)}%` }} />
                </div>
              </div>
            </div>

            <div className="lab-foot">
              <div className="lists">
                {s.allowlist.map((a) => (
                  <span key={a} className="allow">
                    ✓ {a}
                  </span>
                ))}
                {s.blocklist.map((a) => (
                  <span key={a} className="block">
                    ✕ {a}
                  </span>
                ))}
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <button className={`kill ${s.paused ? "on" : ""}`} onClick={() => leash.setPaused(!s.paused)} aria-pressed={s.paused}>
                  Kill switch <span className="switch" />
                </button>
                <button
                  className="btn btn-sm btn-ghost"
                  onClick={() => {
                    leash.reset();
                    setLast(null);
                  }}
                >
                  Reset
                </button>
              </div>
            </div>
            <p className="lab-note">
              This panel runs the leash's rules in your browser, in the contract's order. The real leash is{" "}
              <a href={LEASH} target="_blank" rel="noreferrer">
                live on NEAR testnet
              </a>
              ; its decisions are below.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
