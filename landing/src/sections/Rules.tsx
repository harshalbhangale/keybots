import { useTilt } from "../lib/hooks";

const RULES = [
  { id: "R1", res: "blocked", title: "The kill switch is on", body: "One switch stops every agent at once. Only you can turn it back off." },
  { id: "R2", res: "panic", title: "The caller isn't a registered agent", body: "Nothing happens. Only agents you added can ask the leash at all." },
  { id: "R3", res: "blocked", title: "The receiver is on the blocklist", body: "An agent can report a scammer with evidence, and the report blocks it straight away." },
  { id: "R4", res: "blocked", title: "Over the per-payment cap", body: "Each agent has its own cap: 0.5 NEAR per payment on testnet." },
  { id: "R5", res: "blocked", title: "Past the daily cap", body: "1 NEAR a day per agent. A day is a UTC day by block time." },
  { id: "R6", res: "pending", title: "Untrusted agent, receiver not allowed", body: "Someone else's words can't pay a stranger. It waits for you." },
  { id: "R7", res: "pending", title: "The agent asked you", body: "The server's check warned (new account, never paid), so the agent asks." },
  { id: "R0", res: "blocked", title: "Not enough NEAR in the leash", body: "Balance minus what the contract's storage needs. Otherwise: paid." },
];

function Rule({ r, i }: { r: (typeof RULES)[number]; i: number }) {
  const ref = useTilt<HTMLDivElement>(12);
  return (
    <div data-reveal style={{ ["--d" as string]: `${(i % 4) * 0.06}s` }}>
      <div className="rule glass tilt" ref={ref}>
        <div className="tilt-shine" />
        <div className="code">
          <b>{r.id}</b>
          <span className={`res ${r.res}`}>{r.res === "panic" ? "no-op" : r.res === "pending" ? "waits" : "blocked"}</span>
        </div>
        <h3>{r.title}</h3>
        <p>{r.body}</p>
      </div>
    </div>
  );
}

export default function Rules() {
  return (
    <section className="section" id="rules">
      <div className="wrap">
        <div className="section-head">
          <span className="eyebrow" data-reveal>
            The rules, in order
          </span>
          <h2 className="h-lg" data-reveal>
            The first rule that fires <span className="lime">decides.</span>
          </h2>
          <p className="lede" data-reveal>
            <code>pay(receiver, amount, memo)</code> runs these checks in this order, every time. Every decision is a NEP-297
            event on chain, and each rule has a test in <code>contracts/leash/src/lib.rs</code>.
          </p>
        </div>
        <div className="rules">
          {RULES.map((r, i) => (
            <Rule key={r.id} r={r} i={i} />
          ))}
        </div>
      </div>
    </section>
  );
}
