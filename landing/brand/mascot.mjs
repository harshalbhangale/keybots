// AIRKEY mascot: a mechanical key that gets excited and clicks itself.
// node landing/brand/mascot.mjs → out/mascot.svg, mascot.png, mascot-click.png, frames/, then make.sh joins a GIF and MP4.
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, "../video/package.json"));
const { Resvg } = require("@resvg/resvg-js");
const out = join(here, "out");
const frames = join(out, "frames");
rmSync(frames, { recursive: true, force: true });
mkdirSync(frames, { recursive: true });

const W = "#FFFFFF";
const K = "#000000";
const LIME = "#C6F25A";
const CX = 120; // the key's centre line
const REST = 190; // where the cap's bottom corner sits when fully pressed

const pts = (a) => a.map((q, i) => `${i ? "L" : "M"}${q[0].toFixed(1)} ${q[1].toFixed(1)}`).join(" ") + " Z";
const lerp = (a, b, k) => a + (b - a) * k;
const ease = (k) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
const clamp = (x) => Math.max(0, Math.min(1, x));

/** The switch housing: a low slab with a dark socket the stem comes out of. */
function housing(pulse = 0) {
  const s = 1 + pulse * 0.04;
  const top = 168, hw = 70 * s, hh = 34 * s, depth = 16;
  const T = [CX, top - hh], L = [CX - hw, top], R = [CX + hw, top], C = [CX, top + hh];
  const BL = [L[0], L[1] + depth], BR = [R[0], R[1] + depth], B = [C[0], C[1] + depth];
  return `
    <path d="${pts([T, R, BR, B, BL, L])}" fill="${W}" stroke="${W}" stroke-width="10" stroke-linejoin="round"/>
    <path d="M${L[0]} ${L[1]} L${C[0]} ${C[1]} L${R[0]} ${R[1]} M${C[0]} ${C[1]} L${B[0]} ${B[1]}" fill="none" stroke="${K}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${pts([[CX, top - 14], [CX + 28, top], [CX, top + 14], [CX - 28, top]])}" fill="${K}" stroke="${K}" stroke-width="6" stroke-linejoin="round"/>`;
}

/** The lime cross stem, from the socket up to the cap. */
function stem(lift) {
  if (lift < 2) return "";
  const top = 168 - lift - 4;
  return `<g fill="${LIME}">
    <rect x="${CX - 5}" y="${top}" width="10" height="${lift + 6}" rx="3"/>
    <rect x="${CX - 13}" y="${top + 4}" width="26" height="8" rx="3" opacity=".9"/></g>`;
}

/** The cap with its face. lift raises it, sy squashes or stretches it from its bottom corner. */
function cap(lift, sy, mood) {
  const by = REST - 22 - lift; // bottom corner of the cap
  const rel = { T: [0, -107], L: [-41, -87], R: [41, -87], C: [0, -66], BL: [-54, -32], BR: [54, -32], B: [0, 0] };
  const sx = 1 + (1 - sy) * 0.6; // keep the volume: squash wider, stretch thinner
  const P = Object.fromEntries(Object.entries(rel).map(([k, [x, y]]) => [k, [CX + x * sx, by + y * sy]]));
  const body = `<path d="${pts([P.T, P.R, P.BR, P.B, P.BL, P.L])}" fill="${W}" stroke="${W}" stroke-width="14" stroke-linejoin="round"/>`;
  const seams = `<path d="M${P.L[0] - 2} ${P.L[1] + 1} L${P.C[0]} ${P.C[1]} L${P.R[0] + 2} ${P.R[1] + 1} M${P.C[0]} ${P.C[1]} L${P.B[0]} ${P.B[1] - 2}" fill="none" stroke="${K}" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>`;
  const d = (x, y) => [CX + x * sx, by + y * sy];
  const dish = `<path d="${pts([d(0, -99), d(26, -87), d(0, -75), d(-26, -87)])}" fill="none" stroke="${K}" stroke-width="3.5" stroke-linejoin="round"/>`;
  // eyes on the front face
  const e1 = d(13, -52), e2 = d(31, -61);
  let eyes;
  if (mood === "happy") {
    eyes = `<g fill="none" stroke="${K}" stroke-width="6.5" stroke-linecap="round">
      <path d="M${e1[0] - 6} ${e1[1] + 4} q6 -10 12 0"/><path d="M${e2[0] - 6} ${e2[1] + 4} q6 -10 12 0"/></g>`;
  } else {
    const h = mood === "excited" ? 30 : 23;
    const w = mood === "excited" ? 11 : 9.5;
    eyes = `<g fill="${K}">
      <rect x="${e1[0] - w / 2}" y="${e1[1] - h / 2}" width="${w}" height="${h * sy}" rx="${w / 2}"/>
      <rect x="${e2[0] - w / 2}" y="${e2[1] - h / 2}" width="${w}" height="${h * sy}" rx="${w / 2}"/></g>`;
    if (mood === "excited") {
      eyes += `<g fill="${W}"><circle cx="${e1[0] + 1.5}" cy="${e1[1] - h / 2 + 6}" r="2.4"/><circle cx="${e2[0] + 1.5}" cy="${e2[1] - h / 2 + 6}" r="2.4"/></g>`;
    }
  }
  return body + seams + dish + eyes;
}

/** The click: short lines bursting from the base, and a sparkle. */
function burst(k) {
  if (k <= 0 || k >= 1) return "";
  const r0 = 76 + k * 26, r1 = r0 + 22 * (1 - k * 0.6);
  const a = [160, 185, 205, 335, 355, 20].map((deg) => (deg * Math.PI) / 180);
  const lines = a
    .map((t) => `<path d="M${CX + Math.cos(t) * r0} ${168 + Math.sin(t) * r0 * 0.55} L${CX + Math.cos(t) * r1} ${168 + Math.sin(t) * r1 * 0.55}" />`)
    .join("");
  return `<g stroke="${W}" stroke-width="7" stroke-linecap="round" opacity="${1 - k * k}">${lines}</g>`;
}

const spark = (x, y, s, fill = W, op = 1) =>
  s <= 0
    ? ""
    : `<path opacity="${op}" d="M${x} ${y - s} Q${x + s * 0.18} ${y - s * 0.18} ${x + s} ${y} Q${x + s * 0.18} ${y + s * 0.18} ${x} ${y + s} Q${x - s * 0.18} ${y + s * 0.18} ${x - s} ${y} Q${x - s * 0.18} ${y - s * 0.18} ${x} ${y - s} Z" fill="${fill}"/>`;

/** Speed lines on the left while it rises (the "air" from concept 3). */
function speed(k) {
  if (k <= 0) return "";
  return `<g stroke="${W}" stroke-width="7" stroke-linecap="round" opacity="${k}">
    <path d="M22 ${92} H${22 + 26 * k}"/><path d="M14 ${112} H${14 + 20 * k}"/><path d="M24 ${132} H${24 + 22 * k}"/></g>`;
}

/** One moment of the loop, t in [0, 1). */
function scene(t) {
  let lift, sy = 1, mood = "dots", hit = 0, sp = 0, spd = 0, pulse = 0;
  if (t < 0.3) {
    // idle: a gentle bob on its spring
    lift = 14 + Math.sin((t / 0.3) * Math.PI * 2) * 2;
  } else if (t < 0.52) {
    // excited: it rises and stretches, eyes go wide
    const k = ease((t - 0.3) / 0.22);
    lift = lerp(14, 40, k);
    sy = lerp(1, 1.1, k);
    mood = "excited";
    spd = k;
    sp = k;
  } else if (t < 0.58) {
    // click: it slams itself down
    const k = (t - 0.52) / 0.06;
    lift = lerp(40, 0, k * k);
    sy = lerp(1.1, 0.8, k);
    mood = "excited";
    spd = 1 - k;
  } else if (t < 0.74) {
    // impact: squashed, happy, the click bursts out
    const k = (t - 0.58) / 0.16;
    lift = 0;
    sy = lerp(0.8, 0.95, ease(k));
    mood = "happy";
    hit = k;
    pulse = 1 - k;
    sp = 1 - k;
  } else {
    // spring back up with a little overshoot
    const k = (t - 0.74) / 0.26;
    lift = 14 + Math.sin(k * Math.PI) * 8 * (1 - k) - 14 * Math.pow(1 - k, 3);
    sy = lerp(0.95, 1, k) + Math.sin(k * Math.PI * 2) * 0.03 * (1 - k);
    mood = k < 0.5 ? "happy" : "dots";
  }
  return `
    ${speed(spd)}
    ${housing(pulse)}
    ${stem(lift)}
    ${cap(lift, sy, mood)}
    ${burst(hit)}
    ${spark(186, 40, 15 * sp, W, sp)}${spark(206, 66, 7 * sp, LIME, sp)}`;
}

const svg = (inner, bg = K, size = 480) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="${size}" height="${size}"><rect width="240" height="240" fill="${bg}"/>${inner}</svg>`;
const png = (markup, w) => new Resvg(markup, { fitTo: { mode: "width", value: w } }).render().asPng();

// Stills: the logo at rest (stem showing) and at the click.
const still = svg(`${housing(0)}${stem(14)}${cap(14, 1, "dots")}`);
writeFileSync(join(out, "mascot.svg"), still);
writeFileSync(join(out, "mascot.png"), png(still, 1024));
const clickStill = svg(scene(0.6));
writeFileSync(join(out, "mascot-click.png"), png(clickStill, 1024));

// The loop: 2.4 s at 30 fps.
const N = 72;
for (let i = 0; i < N; i++) {
  writeFileSync(join(frames, `f${String(i).padStart(3, "0")}.png`), png(svg(scene(i / N)), 480));
}
console.log(`wrote mascot.svg, mascot.png, mascot-click.png and ${N} frames`);
