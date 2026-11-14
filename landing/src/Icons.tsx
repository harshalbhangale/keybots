/** NEAR's N on a dark green tile, as in NEAR's own app icon. */
export function NearTile({ size = "1em", label = true }: { size?: string | number; label?: boolean }) {
  return (
    <span className="near-tile" style={{ width: size, height: size }} role={label ? "img" : undefined} aria-label={label ? "NEAR" : undefined} aria-hidden={label ? undefined : true}>
      <svg viewBox="0 0 20.2 19.6" aria-hidden>
        <path
          d="M15.3 1.4 11.6 6.9c-.3.4.3.9.6.6l3.7-3.2c.1-.1.3 0 .3.1v9.9c0 .2-.2.2-.3.1L4.7.6C4.3.2 3.8 0 3.2 0h-.4C1.3 0 0 1.3 0 2.8v13.9c0 1.6 1.3 2.8 2.8 2.8.9 0 1.8-.5 2.3-1.3l3.7-5.5c.3-.4-.3-.9-.6-.6l-3.7 3.2c-.1.1-.3 0-.3-.1V5.4c0-.2.2-.2.3-.1l11.2 13.6c.4.4 1 .6 1.5.6h.4c1.6 0 2.8-1.3 2.8-2.8V2.8C20.2 1.3 18.9 0 17.4 0c-1 0-1.9.5-2.4 1.4z"
          fill="currentColor"
        />
      </svg>
    </span>
  );
}

/** Line icons for the page, drawn on a 24 grid. */
export function Ico({ n, s = 20 }: { n: string; s?: number }) {
  const p = {
    width: s,
    height: s,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.7,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  switch (n) {
    case "lock":
      return <svg {...p}><rect x="4.5" y="10.5" width="15" height="10" rx="2.5" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5M12 14.5v2" /></svg>;
    case "chip":
      return <svg {...p}><rect x="6" y="6" width="12" height="12" rx="2" /><rect x="9.5" y="9.5" width="5" height="5" rx="1" /><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3" /></svg>;
    case "key":
      return <svg {...p}><circle cx="8" cy="15" r="4" /><path d="m11 12 8.5-8.5M16 7l2.5 2.5M14 9l2 2" /></svg>;
    case "eye-off":
      return <svg {...p}><path d="M3 3l18 18M10.6 6.1A9.6 9.6 0 0 1 12 6c5 0 8.5 4.2 9.5 6-.4.8-1.3 2-2.5 3.2M6.6 7.6C4.6 9 3.2 10.9 2.5 12c1 1.8 4.5 6 9.5 6 1.6 0 3-.4 4.3-1.1M9.9 9.9a3 3 0 0 0 4.2 4.2" /></svg>;
    case "shield":
      return <svg {...p}><path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6z" /><path d="m8.8 12 2.2 2.2 4.2-4.4" /></svg>;
    case "face":
      return <svg {...p}><path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M9 9.5v1M15 9.5v1M12 9.5v3.5h-1M9.5 16a4 4 0 0 0 5 0" /></svg>;
    case "stop":
      return <svg {...p}><circle cx="12" cy="12" r="9" /><rect x="9" y="9" width="6" height="6" rx="1" /></svg>;
    case "pay":
      return <svg {...p}><path d="M7 17 17 7M9 7h8v8" /></svg>;
    case "swap":
      return <svg {...p}><path d="M4 8h13l-3-3M20 16H7l3 3" /></svg>;
    case "check":
      return <svg {...p}><circle cx="11" cy="11" r="6.5" /><path d="m20 20-4.4-4.4" /></svg>;
    case "follow":
      return <svg {...p}><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20a6.5 6.5 0 0 1 13 0M18 8v6M15 11h6" /></svg>;
    case "x":
      return <svg {...p}><path d="M6 6l12 12M18 6 6 18" /></svg>;
    case "ok":
      return <svg {...p}><path d="M5 12.5 10 17l9-10" /></svg>;
    case "spark":
      return <svg {...p}><path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18" /></svg>;
    default:
      return null;
  }
}
