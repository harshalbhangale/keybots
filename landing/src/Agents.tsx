import { Ico } from "./Icons";
import { REPO } from "./ui";

/** Outside agents (Claude Code, anything that speaks MCP) asking Keybots for money. */
const STEPS: { n: string; title: string; text: string }[] = [
  { n: "01", title: "The agent asks", text: "Claude Code calls keybots_pay. It lands in the lane for things you didn't type, with that lane's small limits." },
  { n: "02", title: "NEAR checks it", text: "Spend Limits runs the rules on chain: per-payment cap, daily cap, blocked list, allowed list. Over the cap is refused, whoever asked." },
  { n: "03", title: "Your keyboard lights up", text: "Claude Code shows up live in the Keybots panel: what it asked for, and that it's waiting on you." },
  { n: "04", title: "Face ID says yes", text: "Hold to approve. Your phone signs it. The agent never holds a key and never sees one." },
];

export function Agents() {
  return (
    <div className="mx">
      <div className="mx-head" data-reveal>
        <span className="pv-badge">
          <Ico n="key" s={15} /> Agents, on a leash
        </span>
        <h2 className="z-h2">
          Any agent can ask. <span className="grad">Only you can say yes.</span>
        </h2>
        <p className="mx-sub">
          Plug Keybots into Claude Code, or any agent that speaks MCP. It gets a wallet it can ask, not one it can drain.
        </p>
      </div>

      <div className="mx-grid">
        <div className="mx-term" data-reveal>
          <div className="mx-term-bar">
            <i /><i /><i />
            <span>claude</span>
          </div>
          <pre>
            <span className="mx-me">&gt; pay vendor.testnet 0.3 for the logo</span>
            {"\n\n"}
            <span className="mx-tool">● keybots.keybots_pay</span>
            <span className="mx-dim">(to: "vendor.testnet", amount: "0.3")</span>
            {"\n"}
            <span className="mx-dim">  ⎿ </span>
            <span className="mx-wait">Waiting for you:</span> vendor.testnet isn't on your allowed list
            {"\n\n"}
            <span className="mx-me">&gt; pay vendor.testnet 5</span>
            {"\n\n"}
            <span className="mx-tool">● keybots.keybots_pay</span>
            <span className="mx-dim">(to: "vendor.testnet", amount: "5")</span>
            {"\n"}
            <span className="mx-dim">  ⎿ </span>
            <span className="mx-no">Refused on chain:</span> over the per-payment cap
          </pre>
          <div className="mx-install">
            <span>Add it in one line</span>
            <code>claude mcp add keybots -- node tools/keybots-mcp/index.mjs</code>
          </div>
        </div>

        <div className="mx-shots" data-reveal>
          <figure>
            <img src="/screens/agent-keyboard.jpg" alt="The Keybots keyboard panel: Claude Code, agent, waiting for you, asked to pay vendor.testnet 0.3 NEAR" loading="lazy" />
            <figcaption>Live in your keyboard</figcaption>
          </figure>
          <figure>
            <img src="/screens/agent-approve.jpg" alt="The Keybots app: 0.3 NEAR to vendor.testnet from Claude Code, hold to approve with Face ID" loading="lazy" />
            <figcaption>Yours to approve</figcaption>
          </figure>
        </div>
      </div>

      <ol className="mx-steps">
        {STEPS.map((s, k) => (
          <li key={s.n} data-reveal style={{ transitionDelay: `${k * 70}ms` }}>
            <span className="mx-n">{s.n}</span>
            <b>{s.title}</b>
            <p>{s.text}</p>
          </li>
        ))}
      </ol>

      <p className="mx-foot" data-reveal>
        Real, not a mock-up: the shots above are a testnet request from Claude Code.{" "}
        <a href={`${REPO}/tree/main/tools/keybots-mcp`} target="_blank" rel="noreferrer">The MCP server ↗</a>
      </p>
    </div>
  );
}
