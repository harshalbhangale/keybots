import { useEffect, useState } from "react";
import { GitHub, Mark, REPO } from "../ui";

const LINKS = [
  ["Problem", "#problem"],
  ["Leash", "#lab"],
  ["Rules", "#rules"],
  ["App", "#app"],
  ["Testnet", "#testnet"],
  ["How it's built", "#built"],
];

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 40);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  return (
    <nav className={`nav ${scrolled ? "scrolled" : ""}`}>
      <a href="#top" className="brand" aria-label="AIRKEY home">
        <Mark /> AIRKEY
      </a>
      <div className="nav-links">
        {LINKS.map(([label, href]) => (
          <a key={href} href={href}>
            {label}
          </a>
        ))}
      </div>
      <a className="btn btn-sm btn-lime" href={REPO} target="_blank" rel="noreferrer">
        <GitHub size={14} /> GitHub
      </a>
    </nav>
  );
}
