import { useEffect } from "react";
import Lenis from "lenis";
import Nav from "./sections/Nav";
import Hero from "./sections/Hero";
import { Marquee, Pillars, Problem } from "./sections/Story";
import Lab from "./sections/Lab";
import Rules from "./sections/Rules";
import Phones from "./sections/Phones";
import Testnet from "./sections/Testnet";
import Built from "./sections/Built";
import Closing from "./sections/Closing";
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
        <Rules />
        <Phones />
        <Testnet />
        <Built />
      </main>
      <Closing />
      <div className="grain" />
    </>
  );
}
