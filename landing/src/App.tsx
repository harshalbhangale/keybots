import { useEffect } from "react";
import Lenis from "lenis";
import Nav from "./sections/Nav";
import Hero from "./sections/Hero";
import { Marquee, Pillars, Problem } from "./sections/Story";
import Lab from "./sections/Lab";
import { prefersReducedMotion, useRevealAll } from "./lib/hooks";

export default function App() {
  useRevealAll();

  useEffect(() => {
    if (prefersReducedMotion()) return;
    const lenis = new Lenis({ lerp: 0.11, anchors: { offset: -80 } });
    let raf = requestAnimationFrame(function loop(t) {
      lenis.raf(t);
      raf = requestAnimationFrame(loop);
    });
    return () => {
      cancelAnimationFrame(raf);
      lenis.destroy();
    };
  }, []);

  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Marquee />
        <Problem />
        <Pillars />
        <Lab />
      </main>
      <div className="grain" />
    </>
  );
}
