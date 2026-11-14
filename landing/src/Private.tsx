import { Ico } from "./Icons";

/** What stays private, and how NEAR keeps it that way. */
const PRIV: { icon: string; title: string; text: string }[] = [
  { icon: "chip", title: "Private AI on NEAR AI Cloud", text: "Every answer signed, and the hardware it ran on (Intel TDX + NVIDIA GPU) verified." },
  { icon: "key", title: "Your key stays on your phone", text: "The owner key is made on the phone, kept in its Keychain and used only after Face ID. The server just passes on what the phone signed." },
  { icon: "lock", title: "Agents get small keys", text: "Each agent has its own NEAR account and a key that can only ask the Spend Limits contract to pay. It can't drain the wallet." },
  { icon: "eye-off", title: "Addresses, never secrets", text: "The vault keeps the addresses you paste often. Keys and seed phrases are never stored there." },
];

export function Private() {
  return (
    <div className="pv">
      <div className="pv-head" data-reveal>
        <span className="pv-badge">
          <Ico n="shield" s={15} /> Private by design
        </span>
        <h2 className="z-h2">
          It sees what you type. <span className="grad">It keeps it yours.</span>
        </h2>
      </div>
      <div className="pv-grid">
        {PRIV.map((x, k) => (
          <article className="pv-card" key={x.title} data-reveal style={{ transitionDelay: `${k * 70}ms` }}>
            <span className="pv-ico">
              <Ico n={x.icon} s={22} />
            </span>
            <b>{x.title}</b>
            <p>{x.text}</p>
          </article>
        ))}
      </div>
    </div>
  );
}
