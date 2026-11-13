import { useEffect, useRef } from "react";
import { scene, setTheme } from "../brand/core.mjs";

setTheme("mono");
const PERIOD = 2400;
const svg = (t: number) => `<svg viewBox="0 0 240 240" xmlns="http://www.w3.org/2000/svg">${scene(t)}</svg>`;

/** The AIRKEY mascot, drawn live: it gets excited and clicks itself. Click or tap it to make it click now. */
export default function Mascot({ size = 300, label = "The AIRKEY mascot, a key that clicks itself" }: { size?: number; label?: string }) {
  const box = useRef<HTMLDivElement>(null);
  const start = useRef(performance.now());

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      el.innerHTML = svg(0.12);
      return;
    }
    let raf = 0;
    let live = true;
    const tick = () => {
      if (live) el.innerHTML = svg((((performance.now() - start.current) % PERIOD) / PERIOD + 1) % 1);
      raf = requestAnimationFrame(tick);
    };
    const io = new IntersectionObserver(([e]) => (live = e.isIntersecting), { rootMargin: "100px" });
    io.observe(el);
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      io.disconnect();
    };
  }, []);

  // Jump to the moment it gets excited, so the click follows right away.
  const poke = () => (start.current = performance.now() - PERIOD * 0.3);

  return (
    <div
      ref={box}
      className="mascot"
      style={{ width: size, height: size }}
      role="img"
      aria-label={label}
      onPointerDown={poke}
    />
  );
}
