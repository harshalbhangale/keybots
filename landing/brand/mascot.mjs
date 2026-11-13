// AIRKEY mascot: a lime mechanical key that gets excited and clicks itself. Colour, sticker style.
// node landing/brand/mascot.mjs → out/mascot*.svg|png, out/icon.*, out/frames/, out/preview.png
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

const INK = "#0B0C0A"; // outline
const LIME = { top: "#E4FF8F", front: "#C6F25A", side: "#93BD2E", dish: "#D4FA70" };
// Cap colour themes: the lime sticker, and a monochrome white cap with lime only on the stem.
const THEMES = {
  lime: { cap: LIME, stem: "#FF5C8A", led: "#FF5C8A", cheeks: true },
  mono: { cap: { top: "#FFFFFF", front: "#EDEDEF", side: "#B9BAC0", dish: "#F6F6F7" }, stem: "#C6F25A", led: "#C6F25A", cheeks: false },
};
let TH = THEMES.lime;
const SW = { top: "#4A4C55", front: "#2B2C32", side: "#1C1D21" }; // switch housing
const STEM = "#FF5C8A";
const PINK = "#FF8FAB";
const GOLD = "#FFD84A";
const CX = 120;
const SOCKET_Y = 176;

const poly = (a) => a.map((q, i) => `${i ? "L" : "M"}${q[0].toFixed(1)} ${q[1].toFixed(1)}`).join(" ") + " Z";
const lerp = (a, b, k) => a + (b - a) * k;
const ease = (k) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
const face = (pts, fill, sw = 4) => `<path d="${poly(pts)}" fill="${fill}" stroke="${INK}" stroke-width="${sw}" stroke-linejoin="round"/>`;

/** The switch: a charcoal slab with a dark socket. */
function housing(pulse = 0) {
  const s = 1 + pulse * 0.035;
  const top = SOCKET_Y, hw = 78 * s, hh = 32 * s, depth = 18;
  const T = [CX, top - hh], L = [CX - hw, top], R = [CX + hw, top], C = [CX, top + hh];
  const BL = [L[0], L[1] + depth], BR = [R[0], R[1] + depth], B = [C[0], C[1] + depth];
  return [
    `<path d="${poly([T, R, BR, B, BL, L])}" fill="${INK}" stroke="${INK}" stroke-width="12" stroke-linejoin="round"/>`,
    face([L, C, B, BL], SW.side, 3),
    face([C, R, BR, B], SW.front, 3),
    face([T, R, C, L], SW.top, 3),
    face([[CX, top - 13], [CX + 30, top], [CX, top + 13], [CX - 30, top]], "#101114", 3),
    // the LED strip along the front of the switch
    `<path d="M${L[0] + 12} ${L[1] + 9} L${C[0]} ${C[1] + 9} L${R[0] - 12} ${R[1] + 9}" fill="none" stroke="${TH.led}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>`,
  ].join("");
}

/** The pink cross stem, from the socket to the cap. */
function stem(lift) {
  if (lift < 3) return "";
  const top = SOCKET_Y - lift - 2;
  return `<g fill="${TH.stem}" stroke="${INK}" stroke-width="3" stroke-linejoin="round">
    <rect x="${CX - 6}" y="${top}" width="12" height="${lift + 4}" rx="3"/>
    <rect x="${CX - 15}" y="${top + 3}" width="30" height="9" rx="3"/></g>`;
}

/** The lime cap with its face. sy squashes (<1) or stretches (>1) it from its bottom corner. */
function cap(lift, sy, mood) {
  const by = SOCKET_Y + 26 - lift;
  const sx = 1 + (1 - sy) * 0.7;
  const at = (x, y) => [CX + x * sx, by + y * sy];
  const T = at(0, -100), L = at(-60, -76), R = at(60, -76), C = at(0, -52), BL = at(-72, -26), BR = at(72, -26), B = at(0, 0);
  let s = `<path d="${poly([T, R, BR, B, BL, L])}" fill="${INK}" stroke="${INK}" stroke-width="13" stroke-linejoin="round"/>`;
  s += face([L, C, B, BL], TH.cap.side);
  s += face([C, R, BR, B], TH.cap.front);
  s += face([T, R, C, L], TH.cap.top);
  // the dish, and a shine on the top face
  s += `<path d="${poly([at(0, -92), at(42, -76), at(0, -60), at(-42, -76)])}" fill="${TH.cap.dish}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round" opacity=".9"/>`;
  s += `<path d="M${at(-30, -82)[0]} ${at(-30, -82)[1]} L${at(-14, -88)[0]} ${at(-14, -88)[1]}" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".85"/>`;
  // the face, on the front
  const e1 = at(22, -50), e2 = at(48, -62), mouth = at(36, -34), ch1 = at(14, -36), ch2 = at(60, -48);
  if (mood === "happy") {
    s += `<g fill="none" stroke="${INK}" stroke-width="5" stroke-linecap="round">
      <path d="M${e1[0] - 7} ${e1[1] + 3} q7 -11 14 0"/><path d="M${e2[0] - 7} ${e2[1] + 3} q7 -11 14 0"/></g>`;
    s += `<path d="M${mouth[0] - 10} ${mouth[1] - 4} q10 14 20 -2 z" fill="${INK}"/><path d="M${mouth[0] - 4} ${mouth[1] + 3} q5 4 9 -1" fill="${TH.cheeks ? STEM : "#FF8FAB"}"/>`;
  } else {
    const big = mood === "excited";
    const rx = big ? 7 : 6, ry = big ? 10.5 : 8.5;
    for (const e of [e1, e2]) {
      s += `<ellipse cx="${e[0]}" cy="${e[1]}" rx="${rx}" ry="${ry * Math.min(1, sy + 0.1)}" fill="${INK}"/>`;
      s += `<circle cx="${e[0] + 2}" cy="${e[1] - ry * 0.4}" r="${big ? 3 : 2.4}" fill="#fff"/>`;
    }
    s += big
      ? `<ellipse cx="${mouth[0]}" cy="${mouth[1] - 2}" rx="5.5" ry="6.5" fill="${INK}"/>`
      : `<path d="M${mouth[0] - 7} ${mouth[1] - 5} q7 7 14 -3" fill="none" stroke="${INK}" stroke-width="4" stroke-linecap="round"/>`;
  }
  if (TH.cheeks) s += `<ellipse cx="${ch1[0]}" cy="${ch1[1]}" rx="6" ry="3.5" fill="${PINK}" opacity=".85"/><ellipse cx="${ch2[0]}" cy="${ch2[1]}" rx="6" ry="3.5" fill="${PINK}" opacity=".85"/>`;
  return s;
}

const spark = (x, y, r, fill, op = 1) =>
  r <= 0
    ? ""
    : `<path opacity="${op}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round" fill="${fill}" d="M${x} ${y - r} Q${x + r * 0.2} ${y - r * 0.2} ${x + r} ${y} Q${x + r * 0.2} ${y + r * 0.2} ${x} ${y + r} Q${x - r * 0.2} ${y + r * 0.2} ${x - r} ${y} Q${x - r * 0.2} ${y - r * 0.2} ${x} ${y - r} Z"/>`;

function burst(k) {
  if (k <= 0 || k >= 1) return "";
  const r0 = 88 + k * 24, r1 = r0 + 22 * (1 - k * 0.6);
  const a = [160, 185, 205, 335, 355, 20].map((d) => (d * Math.PI) / 180);
  const cols = [GOLD, STEM, LIME.front, GOLD, STEM, LIME.front];
  return a
    .map(
      (t, i) =>
        `<path d="M${CX + Math.cos(t) * r0} ${SOCKET_Y + Math.sin(t) * r0 * 0.5} L${CX + Math.cos(t) * r1} ${SOCKET_Y + Math.sin(t) * r1 * 0.5}" stroke="${cols[i]}" stroke-width="7" stroke-linecap="round" opacity="${1 - k * k}"/>`,
    )
    .join("");
}

function speed(k) {
  if (k <= 0) return "";
  return `<g stroke="#fff" stroke-width="6" stroke-linecap="round" opacity="${k}">
    <path d="M14 96 H${14 + 22 * k}"/><path d="M8 116 H${8 + 16 * k}"/><path d="M16 136 H${16 + 18 * k}"/></g>`;
}

/** One moment of the 2.4 s loop, t in [0, 1). */
function scene(t) {
  let lift, sy = 1, mood = "dots", hit = 0, sp = 0, spd = 0, pulse = 0;
  if (t < 0.3) {
    lift = 16 + Math.sin((t / 0.3) * Math.PI * 2) * 2;
  } else if (t < 0.52) {
    const k = ease((t - 0.3) / 0.22);
    lift = lerp(16, 42, k);
    sy = lerp(1, 1.1, k);
    mood = "excited";
    spd = k;
    sp = k;
  } else if (t < 0.58) {
    const k = (t - 0.52) / 0.06;
    lift = lerp(42, 0, k * k);
    sy = lerp(1.1, 0.8, k);
    mood = "excited";
    spd = 1 - k;
  } else if (t < 0.74) {
    const k = (t - 0.58) / 0.16;
    lift = 0;
    sy = lerp(0.8, 0.95, ease(k));
    mood = "happy";
    hit = k;
    pulse = 1 - k;
    sp = 1 - k;
  } else {
    const k = (t - 0.74) / 0.26;
    lift = 16 + Math.sin(k * Math.PI) * 8 * (1 - k) - 16 * Math.pow(1 - k, 3);
    sy = lerp(0.95, 1, k) + Math.sin(k * Math.PI * 2) * 0.03 * (1 - k);
    mood = k < 0.5 ? "happy" : "dots";
  }
  return `${speed(spd)}${housing(pulse)}${stem(lift)}${cap(lift, sy, mood)}${burst(hit)}${spark(196, 46, 14 * sp, GOLD, sp)}${spark(214, 76, 8 * sp, STEM, sp)}${spark(34, 54, 7 * sp, LIME.front, sp)}`;
}

/** The icon: the whole key at rest, cap on its switch, with room around it. */
const iconArt = () => `<g transform="translate(120 126) scale(0.84) translate(-120 -146)">${housing(0)}${stem(26)}${cap(26, 1, "dots")}</g>`;

const BG = "#0E0F13";
const bgDefs = `<defs><radialGradient id="g" cx="50%" cy="45%" r="60%"><stop offset="0" stop-color="#C6F25A" stop-opacity=".18"/><stop offset="1" stop-color="#C6F25A" stop-opacity="0"/></radialGradient></defs>`;
const svg = (inner, bg = BG, size = 480) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="${size}" height="${size}">${bgDefs}<rect width="240" height="240" fill="${bg}"/>${bg === BG ? '<rect width="240" height="240" fill="url(#g)"/>' : ""}${inner}</svg>`;
const png = (markup, w) => new Resvg(markup, { fitTo: { mode: "width", value: w }, font: { loadSystemFonts: true } }).render().asPng();

// Stills
const rest = `${housing(0)}${stem(26)}${cap(26, 1, "dots")}`;
writeFileSync(join(out, "mascot.svg"), svg(rest));
writeFileSync(join(out, "mascot.png"), png(svg(rest), 1024));
writeFileSync(join(out, "mascot-click.png"), png(svg(scene(0.62)), 1024));
const iconInner = iconArt();
const icon = svg(iconInner, BG, 1024);
writeFileSync(join(out, "icon.svg"), icon);
writeFileSync(join(out, "icon.png"), png(icon, 1024));

// Animation frames
const N = 72;
for (let i = 0; i < N; i++) writeFileSync(join(frames, `f${String(i).padStart(3, "0")}.png`), png(svg(scene(i / N)), 480));

// Side-by-side: lime and mono, each as the hero, app icon sizes, keyboard brand key and home screen.
const PW = 1400, PH = 1000;
let clipN = 0;
const tile = (x, y, sz, r, inner, bg) => {
  const id = `c${clipN++}`;
  return `<svg x="${x}" y="${y}" width="${sz}" height="${sz}" viewBox="0 0 240 240"><defs><clipPath id="${id}"><rect width="240" height="240" rx="${(r / sz) * 240}"/></clipPath></defs><g clip-path="url(#${id})">${bgDefs}<rect width="240" height="240" fill="${bg}"/>${bg === BG ? '<rect width="240" height="240" fill="url(#g)"/>' : ""}${inner}</g></svg>`;
};
const label = (x, y, t, size = 18, fill = "#8e8e93", weight = 400, anchor = "start") =>
  `<text x="${x}" y="${y}" text-anchor="${anchor}" font-family="Helvetica Neue" font-size="${size}" font-weight="${weight}" fill="${fill}">${t}</text>`;

function column(x0, name, note) {
  let c = label(x0, 120, name, 30, "#fff", 700) + label(x0, 150, note, 17);
  // hero: at rest and the click
  c += tile(x0, 175, 290, 40, `${housing(0)}${stem(26)}${cap(26, 1, "dots")}`, BG);
  c += tile(x0 + 310, 175, 290, 40, scene(0.62), BG);
  // app icon sizes
  c += label(x0, 515, "App icon", 18, "#fff", 600);
  [180, 120, 60, 40, 29, 20].reduce((x, sz) => {
    c += tile(x, 535 + (180 - sz) / 2, sz, sz * 0.225, iconArt(), BG);
    return x + sz + 16;
  }, x0);
  // keyboard brand key
  c += label(x0, 765, "Keyboard brand key", 18, "#fff", 600);
  c += `<rect x="${x0}" y="782" width="600" height="80" rx="20" fill="#2a2a2d"/><rect x="${x0 + 12}" y="794" width="66" height="56" rx="14" fill="#111113"/>`;
  c += `<svg x="${x0 + 17}" y="795" width="56" height="56" viewBox="0 0 240 240">${iconArt()}</svg>`;
  c += `<rect x="${x0 + 90}" y="794" width="498" height="56" rx="14" fill="#111113"/>`;
  ["PAY", "TRADE", "CHECK", "VAULT"].forEach((t, i) => (c += label(x0 + 152 + i * 124, 829, t, 15, i === 0 ? "#C6F25A" : "#c7c7cc", 700, "middle")));
  // home screen row
  c += `<rect x="${x0}" y="880" width="600" height="100" rx="24" fill="url(#wall)"/>`;
  [["#FF5C8A"], [null], ["#0A84FF"], ["#34C759"], ["#FF9F0A"]].forEach(([col], i) => {
    const x = x0 + 30 + i * 112;
    c += col ? `<rect x="${x}" y="894" width="72" height="72" rx="16" fill="${col}"/>` : tile(x, 894, 72, 16, iconArt(), BG);
  });
  return c;
}

let sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${PW}" height="${PH}" viewBox="0 0 ${PW} ${PH}"><defs><linearGradient id="wall" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3b2d6e"/><stop offset="1" stop-color="#0f3d3a"/></linearGradient></defs><rect width="100%" height="100%" fill="#08090A"/>`;
sheet += label(70, 64, "AIRKEY mascot: lime or mono", 38, "#fff", 700);
TH = THEMES.lime;
sheet += column(70, "A · Lime", "Playful sticker. Great for stickers, the animation, the site.");
TH = THEMES.mono;
sheet += column(730, "B · Mono + lime light", "Recommended for the app icon and keyboard: one accent.");
sheet += `</svg>`;
writeFileSync(join(out, "preview.png"), png(sheet, PW));
// mono stills and icon too
writeFileSync(join(out, "icon-mono.png"), png(svg(iconArt(), BG, 1024), 1024));
writeFileSync(join(out, "mascot-mono.png"), png(svg(`${housing(0)}${stem(26)}${cap(26, 1, "dots")}`, BG, 1024), 1024));
TH = THEMES.lime;

console.log("wrote stills, icon, preview.png and", N, "frames");
