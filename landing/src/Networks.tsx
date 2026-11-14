import { NearTile } from "./Icons";

/** Where Keybots runs, said exactly: a small contract on mainnet, the full one on testnet. */
export default function Networks() {
  return (
    <div className="nw">
      <h2 className="z-h2 center" data-reveal>
        Live on NEAR. <span className="grad">Mainnet and testnet.</span>
      </h2>
      <div className="nw-grid">
        <article className="nw-card main" data-reveal>
          <div className="nw-top">
            <NearTile size={30} />
            <span>
              <small>NEAR mainnet</small>
              <b>Spend Limits Lite</b>
            </span>
            <span className="nw-live">Live</span>
          </div>
          <a className="nw-acct" href="https://nearblocks.io/address/limits.hellbuddy.near" target="_blank" rel="noreferrer">
            limits.hellbuddy.near ↗
          </a>
          <ul>
            <li className="yes">Real payments</li>
            <li className="yes">Refuses scams on chain</li>
            <li className="yes">Tiny limits, on purpose</li>
            <li className="no">No swaps or approvals yet</li>
          </ul>
          <div className="nw-links">
            <a href="https://nearblocks.io/txns/7hpf2Y28NJetvrAPtpP4oRbJjHEyUeboJAa1zk2xtds" target="_blank" rel="noreferrer">
              A real payment ↗
            </a>
            <a href="https://nearblocks.io/txns/9M4Xys3f6dmMxNFCdt3kQbgimRhnQWktNkr4RqhmaU6e" target="_blank" rel="noreferrer">
              A scam refused ↗
            </a>
          </div>
        </article>

        <article className="nw-card" data-reveal>
          <div className="nw-top">
            <NearTile size={30} />
            <span>
              <small>NEAR testnet</small>
              <b>Spend Limits, the full one</b>
            </span>
            <span className="nw-live test">Live</span>
          </div>
          <a className="nw-acct" href="https://testnet.nearblocks.io/address/leash.airkey-harshal.testnet" target="_blank" rel="noreferrer">
            leash.airkey-harshal.testnet ↗
          </a>
          <ul>
            <li className="yes">Three lanes, each with its own agent</li>
            <li className="yes">Swaps on Rhea</li>
            <li className="yes">Face ID approvals</li>
            <li className="yes">Limits you can change</li>
          </ul>
          <div className="nw-links">
            <a href="https://github.com/harshalbhangale/keybots/blob/main/docs/evidence/testnet-e2e.md" target="_blank" rel="noreferrer">
              Every testnet transaction ↗
            </a>
          </div>
        </article>
      </div>
    </div>
  );
}
