// AIRKEY mascot logo concepts: a keycap with a face, flat white on black.
// node landing/brand/make.mjs   → landing/brand/out/*.svg, *.png and sheet.png
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(here, "../video/package.json"));
const { Resvg } = require("@resvg/resvg-js");
const out = join(here, "out");
mkdirSync(out, { recursive: true });

const W = "#FFFFFF";
const K = "#000000";
const LIME = "#C6F25A";

// The keycap body in 3/4 view: a small top that flares into a wider skirt, like a real cap.
const T = [100, 40], L = [52, 64], R = [148, 64], C = [100, 88], BL = [36, 128], BR = [164, 128], B = [100, 166];
const p = (pts) => pts.map((q, i) => `${i ? "L" : "M"}${q[0]} ${q[1]}`).join(" ") + " Z";

/** The cap: one white silhouette with black gaps where the faces meet, and a dished top. */
function cap({ dx = 0, dy = 0, tab = false, eyes = "dots", rot = 0 } = {}) {
  const g = (s) => `<g transform="translate(${dx} ${dy}) rotate(${rot} 100 104)">${s}</g>`;
  const body = `<path d="${p([T, R, BR, B, BL, L])}" fill="${W}" stroke="${W}" stroke-width="16" stroke-linejoin="round"/>`;
  const seams = `<path d="M${L[0] - 2} ${L[1] + 1} L${C[0]} ${C[1]} L${R[0] + 2} ${R[1] + 1} M${C[0]} ${C[1]} L${B[0]} ${B[1] - 2}" fill="none" stroke="${K}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>`;
  const dish = `<path d="M100 50 L130 64 L100 78 L70 64 Z" fill="none" stroke="${K}" stroke-width="4" stroke-linejoin="round"/>`;
  let face = "";
  if (eyes === "dots") {
    face = `<g><rect x="113" y="98" width="11" height="27" rx="5.5" fill="${K}"/><rect x="133" y="88" width="11" height="27" rx="5.5" fill="${K}"/></g>`;
  } else if (eyes === "happy") {
    face = `<g transform="matrix(1 -0.5 0 1 0 0)" fill="none" stroke="${K}" stroke-width="7" stroke-linecap="round"><path d="M111 176 q7 -11 14 0"/><path d="M131 176 q7 -11 14 0"/></g>`;
  } else if (eyes === "wink") {
    face = `<g transform="matrix(1 -0.5 0 1 0 0)"><rect x="113" y="158" width="11" height="28" rx="5.5" fill="${K}"/><path d="M131 176 q7 -11 14 0" fill="none" stroke="${K}" stroke-width="7" stroke-linecap="round"/></g>`;
  }
  const t = tab ? `<g transform="matrix(1 0.5 0 1 0 0)"><rect x="58" y="44" width="10" height="40" rx="5" fill="${LIME}"/></g>` : "";
  return g(body + seams + dish + face + t);
}

/** A four-point sparkle, like the AI glint on the reference. */
const spark = (x, y, s, fill = W) =>
  `<path d="M${x} ${y - s} Q${x + s * 0.18} ${y - s * 0.18} ${x + s} ${y} Q${x + s * 0.18} ${y + s * 0.18} ${x} ${y + s} Q${x - s * 0.18} ${y + s * 0.18} ${x - s} ${y} Q${x - s * 0.18} ${y - s * 0.18} ${x} ${y - s} Z" fill="${fill}"/>`;

const CONCEPTS = [
  {
    id: "buddy",
    name: "Key buddy",
    line: "A keycap with a face. Simple, friendly, works at 16 px.",
    art: () => cap({ eyes: "dots" }),
  },
  {
    id: "spark",
    name: "Spark",
    line: "The AI glint on top: a key that thinks.",
    art: () => cap({ eyes: "dots", dy: 8 }) + spark(148, 34, 16) + spark(170, 60, 7),
  },
  {
    id: "air",
    name: "Air",
    line: "Speed lines: the key that moves through the air.",
    art: () =>
      cap({ eyes: "dots", dx: 14, rot: -6 }) +
      `<g stroke="${W}" stroke-width="8" stroke-linecap="round"><path d="M10 92 H40"/><path d="M4 114 H30"/><path d="M14 136 H38"/></g>`,
  },
  {
    id: "float",
    name: "Float",
    line: "Hovering over a puff of air.",
    art: () =>
      cap({ eyes: "dots", dy: -16 }) +
      `<g fill="${W}"><circle cx="70" cy="178" r="11"/><circle cx="92" cy="172" r="15"/><circle cx="116" cy="174" r="13"/><circle cx="136" cy="180" r="9"/><rect x="62" y="178" width="80" height="12" rx="6"/></g>`,
  },
  {
    id: "leash",
    name: "Leash",
    line: "On a leash, and happy about it.",
    art: () =>
      cap({ eyes: "dots", dx: -10 }) +
      `<path d="M150 76 C 186 70, 196 120, 170 150 C 160 162, 150 176, 160 188" fill="none" stroke="${W}" stroke-width="7" stroke-linecap="round"/>
       <circle cx="150" cy="76" r="8" fill="${K}" stroke="${W}" stroke-width="5"/>`,
  },
  {
    id: "tab",
    name: "Lime tab",
    line: "Key buddy with AIRKEY's lime side tab.",
    art: () => cap({ eyes: "dots", tab: true }) + spark(150, 36, 10, LIME),
  },
];

const svg = (inner, bg = K) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="512" height="512"><rect width="200" height="200" rx="0" fill="${bg}"/>${inner}</svg>`;
const png = (markup, w) => new Resvg(markup, { fitTo: { mode: "width", value: w }, font: { loadSystemFonts: true } }).render().asPng();

for (const c of CONCEPTS) {
  const s = svg(c.art());
  writeFileSync(join(out, `${c.id}.svg`), s);
  writeFileSync(join(out, `${c.id}.png`), png(s, 512));
}

// Contact sheet: each concept big, plus app-icon and favicon sizes.
const cols = 3;
const cw = 420, ch = 520;
const sheetW = cols * cw + 40, sheetH = Math.ceil(CONCEPTS.length / cols) * ch + 120;
let cells = "";
CONCEPTS.forEach((c, i) => {
  const x = 20 + (i % cols) * cw, y = 100 + Math.floor(i / cols) * ch;
  cells += `<g transform="translate(${x} ${y})">
    <rect x="10" y="10" width="${cw - 20}" height="${ch - 20}" rx="28" fill="#0d0d0e" stroke="#222" />
    <svg x="70" y="30" width="260" height="260" viewBox="0 0 200 200">${c.art()}</svg>
    <rect x="40" y="320" width="96" height="96" rx="22" fill="#000" stroke="#333"/>
    <svg x="48" y="328" width="80" height="80" viewBox="0 0 200 200">${c.art()}</svg>
    <rect x="156" y="344" width="48" height="48" rx="11" fill="${W}"/>
    <svg x="160" y="348" width="40" height="40" viewBox="0 0 200 200"><defs><filter id="inv${i}"><feColorMatrix type="matrix" values="-1 0 0 0 1  0 -1 0 0 1  0 0 -1 0 1  0 0 0 1 0"/></filter></defs><g filter="url(#inv${i})"><rect width="200" height="200" fill="#000"/>${c.art()}</g></svg>
    <svg x="224" y="356" width="24" height="24" viewBox="0 0 200 200">${c.art()}</svg>
    <svg x="258" y="360" width="16" height="16" viewBox="0 0 200 200">${c.art()}</svg>
    <text x="40" y="462" font-family="Helvetica Neue" font-weight="700" font-size="26" fill="#fff">${String(i + 1).padStart(2, "0")}  ${c.name}</text>
    <text x="40" y="490" font-family="Helvetica Neue" font-size="16" fill="#8e8e93">${c.line}</text>
  </g>`;
});
const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="${sheetW}" height="${sheetH}" viewBox="0 0 ${sheetW} ${sheetH}">
  <rect width="100%" height="100%" fill="#000"/>
  <text x="40" y="66" font-family="Helvetica Neue" font-weight="700" font-size="40" fill="#fff">AIRKEY mascot logos</text>
  ${cells}</svg>`;
writeFileSync(join(out, "sheet.png"), png(sheet, sheetW));
console.log("wrote", CONCEPTS.length, "concepts and sheet.png in", out);
