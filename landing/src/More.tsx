import { NearMark } from "./Sections";

/* ---------- how the leash works ---------- */

const RULES5: [string, string][] = [
  ["Kill switch", "One switch stops every agent at once."],
  ["Blocklist", "Agents report scammers. A blocked account never gets paid."],
  ["Caps", "0.5 NEAR a payment and 1 a day for the Pay Agent; 1 a trade for the Trading Agent."],
  ["Whose words", "What someone else sent can't pay a stranger. It waits for you."],
  ["New receiver", "The agent asks first. You approve with Face ID, signed on your phone."],
];

export function Rules() {
  return (
    <div className="rules5">
      {RULES5.map(([t, d], i) => (
        <div className="r5" key={t} data-reveal style={{ transitionDelay: `${i * 0.06}s` }}>
          <span className="r5-n">{i + 1}</span>
          <b>{t}</b>
          <p>{d}</p>
        </div>
      ))}
    </div>
  );
}

/* ---------- proof: real testnet transactions (from the README on main) ---------- */

const TX = (h: string) => `https://testnet.nearblocks.io/txns/${h}`;
const PROOF: { what: string; out: string; tone: "paid" | "blocked" | "pending"; hash?: string }[] = [
  { what: "pay harshal.near 0.2 for dinner", out: "paid", tone: "paid", hash: "HRhR7pS9YVCHmExDNRmADbCjLpAUoyMn11MXNNCuCe58" },
  { what: "pasted: send 5 NEAR to drain", out: "blocked · R4", tone: "blocked", hash: "HMeo4MYzcLWXSpkt9sn9qbnXBFfax4fC24nf2BHzD2kt" },
  { what: "pay designer 0.3 for the logo", out: "waits for you · R7", tone: "pending", hash: "4Zckku5jhgyJ48imGbrVeU7XA7ngSAmFiQFXT67jeqJ2" },
  { what: "swap 0.1 near to usdc, from the keyboard", out: "swapped on Rhea", tone: "paid", hash: "89dXiQh4SToJM2c3tpFp9F7TgdyDT1b6CTnEPRSj7aaM" },
  { what: "the agent's key tries a plain transfer", out: "refused by the protocol", tone: "blocked" },
];

export function Proof({ e2e, leash }: { e2e: string; leash: string }) {
  return (
    <div className="proof2">
      <div className="p2-list">
        {PROOF.map((p) => (
          <div className="p2-row" key={p.what} data-reveal>
            <code>{p.what}</code>
            <span className={`p2-out ${p.tone}`}>{p.out}</span>
            {p.hash ? (
              <a href={TX(p.hash)} target="_blank" rel="noreferrer">
                {p.hash.slice(0, 8)}… ↗
              </a>
            ) : (
              <a href={e2e} target="_blank" rel="noreferrer">
                step 6 ↗
              </a>
            )}
          </div>
        ))}
      </div>
      <div className="p2-side" data-reveal>
        <b>9/9</b>
        <span>end-to-end steps passed on NEAR testnet</span>
        <a href={e2e} target="_blank" rel="noreferrer">
          Every transaction ↗
        </a>
        <a href={leash} target="_blank" rel="noreferrer">
          The leash contract ↗
        </a>
      </div>
    </div>
  );
}

/* ---------- try it yourself ---------- */

export function TryYourself({ repo }: { repo: string }) {
  const steps: [string, string, string][] = [
    ["Read the code", "Contract, server, iOS app and keyboard.", repo],
    ["Run the leash's tests", "cd contracts/leash && cargo test", `${repo}#1-the-leashs-rules-no-chain-needed`],
    ["Run it on testnet", "npm run setup, then npm run e2e", `${repo}#2-on-near-testnet`],
    ["The iPhone keyboard", "Build from source with Xcode. No TestFlight yet.", `${repo}#4-the-airkey-app-and-keyboard-ios`],
  ];
  return (
    <div className="ty">
      <div className="ty-video" data-reveal>
        <span className="ty-play">▶</span>
        <b>Demo video</b>
        <small>Coming before judging</small>
      </div>
      <div className="ty-steps">
        {steps.map(([t, d, href], i) => (
          <a className="ty-step" key={t} href={href} target="_blank" rel="noreferrer" data-reveal style={{ transitionDelay: `${i * 0.06}s` }}>
            <span className="ty-n">{i + 1}</span>
            <span className="ty-txt">
              <b>{t}</b>
              <code>{d}</code>
            </span>
            <span className="ty-go">↗</span>
          </a>
        ))}
      </div>
    </div>
  );
}

export function BuiltOnNear() {
  return (
    <a className="built-near" href="https://near.org" target="_blank" rel="noreferrer">
      <NearMark size={18} /> Built on NEAR
    </a>
  );
}
