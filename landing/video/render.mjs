// Renders the demo video's cards and captions from beats.json to PNGs in build/.
// node render.mjs   (needs @resvg/resvg-js: npm install)
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "build");
mkdirSync(out, { recursive: true });
const cfg = JSON.parse(readFileSync(join(here, "beats.json"), "utf8"));

const W = 1920;
const H = 1080;
const FONT = "Helvetica Neue";
const LIME = "#C6F25A";
const TONE = { paid: LIME, blocked: "#FF5A52", pending: "#F5B841" };
/** Break a line into lines of at most `max` characters, on spaces. */
const wrap = (s, max) =>
  s.split(" ").reduce((lines, w) => {
    const last = lines[lines.length - 1];
    if (last !== undefined && (last + " " + w).length <= max) lines[lines.length - 1] = last + " " + w;
    else lines.push(w);
    return lines;
  }, []);
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// The Keybots logo (the lime NEAR keycap), from the site's public/logo.svg, so there is one source.
const LOGO = readFileSync(join(here, "../public/logo.svg"), "utf8");
const logoInner = LOGO.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
const logoBox = LOGO.match(/viewBox="([^"]+)"/)[1];
let logoN = 0;
const mark = (x, y, s) => {
  // Give each copy its own gradient ids so several logos can share one SVG.
  const k = `L${logoN++}`;
  const inner = logoInner.replace(/id="(\w+)"/g, `id="${k}$1"`).replace(/url\(#(\w+)\)/g, `url(#${k}$1)`);
  return `<svg x="${x}" y="${y}" width="${s}" height="${s}" viewBox="${logoBox}">${inner}</svg>`;
};

const bgDefs = `
  <defs>
    <radialGradient id="glow" cx="50%" cy="45%" r="55%">
      <stop offset="0" stop-color="${LIME}" stop-opacity=".16"/>
      <stop offset="1" stop-color="${LIME}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow2" cx="80%" cy="80%" r="45%">
      <stop offset="0" stop-color="#0A84FF" stop-opacity=".10"/>
      <stop offset="1" stop-color="#0A84FF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="#050505"/>
  <rect width="${W}" height="${H}" fill="url(#glow)"/>
  <rect width="${W}" height="${H}" fill="url(#glow2)"/>`;

const svg = (body, bg = true) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${bg ? bgDefs : ""}${body}</svg>`;

function png(name, markup) {
  const r = new Resvg(markup, { fitTo: { mode: "width", value: W }, font: { loadSystemFonts: true, defaultFontFamily: FONT } });
  writeFileSync(join(out, name), r.render().asPng());
  writeFileSync(join(out, name.replace(/\.png$/, ".svg")), markup);
  console.log("wrote", name);
}

// Background behind a portrait screen recording.
png("bg.png", svg(""));

// Intro card.
png(
  "intro.png",
  svg(`
  ${mark(W / 2 - 70, 330, 140)}
  <text x="${W / 2}" y="600" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="120" letter-spacing="18" fill="#F5F5F7">${esc(cfg.intro.title)}</text>
  <text x="${W / 2}" y="680" text-anchor="middle" font-family="${FONT}" font-size="40" fill="#A1A1A6">${esc(cfg.intro.line)}</text>`),
);

// End card.
png(
  "end.png",
  svg(`
  ${mark(W / 2 - 50, 230, 100)}
  <text x="${W / 2}" y="470" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="96" fill="#F5F5F7">${esc(cfg.end.line1)}</text>
  <text x="${W / 2}" y="590" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="96" fill="${LIME}">${esc(cfg.end.line2)}</text>
  <rect x="${W / 2 - 360}" y="680" width="720" height="78" rx="39" fill="#161618" stroke="#2C2C2E" stroke-width="2"/>
  <text x="${W / 2}" y="732" text-anchor="middle" font-family="${FONT}" font-size="34" fill="#F5F5F7">${esc(cfg.end.url)}</text>
  <text x="${W / 2}" y="850" text-anchor="middle" font-family="${FONT}" font-size="30" fill="#8E8E93">${esc(cfg.end.note)}</text>`),
);

// Captions, two layouts: "side" sits right of a portrait recording; "lower" is a lower third over a landscape one.
cfg.beats.forEach((b, i) => {
  const c = TONE[b.tone] ?? LIME;
  const n = String(i + 1).padStart(2, "0");
  // side: a text block in the right half
  png(
    `cap-side-${n}.png`,
    svg(
      `
    <rect x="1040" y="420" width="6" height="200" rx="3" fill="${c}"/>
    <text x="1080" y="470" font-family="${FONT}" font-size="30" fill="#8E8E93">${n} / ${String(cfg.beats.length).padStart(2, "0")}</text>
    ${wrap(b.title, 22)
      .map((l, k) => `<text x="1080" y="${550 + k * 72}" font-family="${FONT}" font-weight="700" font-size="64" fill="#F5F5F7">${esc(l)}</text>`)
      .join("")}
    ${wrap(b.sub, 40)
      .map((l, k) => `<text x="1080" y="${612 + (wrap(b.title, 22).length - 1) * 72 + k * 44}" font-family="${FONT}" font-size="34" fill="#C7C7CC">${esc(l)}</text>`)
      .join("")}`,
      false,
    ),
  );
  // lower: a glass bar near the bottom
  png(
    `cap-lower-${n}.png`,
    svg(
      `
    <rect x="80" y="860" width="${W - 160}" height="150" rx="36" fill="#0B0B0C" fill-opacity=".86" stroke="#2C2C2E" stroke-width="2"/>
    <rect x="110" y="895" width="8" height="80" rx="4" fill="${c}"/>
    <text x="146" y="932" font-family="${FONT}" font-weight="700" font-size="46" fill="#F5F5F7">${esc(b.title)}</text>
    <text x="146" y="982" font-family="${FONT}" font-size="30" fill="#C7C7CC">${esc(b.sub)}</text>`,
      false,
    ),
  );
});

// The site's share image (1200 × 630), written straight into public/.
{
  const ow = 1200;
  const oh = 630;
  const og = `<svg xmlns="http://www.w3.org/2000/svg" width="${ow}" height="${oh}" viewBox="0 0 ${ow} ${oh}">
    <defs><radialGradient id="og" cx="30%" cy="45%" r="60%"><stop offset="0" stop-color="${LIME}" stop-opacity=".18"/><stop offset="1" stop-color="${LIME}" stop-opacity="0"/></radialGradient></defs>
    <rect width="${ow}" height="${oh}" fill="#050505"/><rect width="${ow}" height="${oh}" fill="url(#og)"/>
    ${mark(80, 90, 150)}
    <text x="80" y="330" font-family="${FONT}" font-weight="700" font-size="76" fill="#F5F5F7">Your keyboard is the AI.</text>
    <text x="80" y="420" font-family="${FONT}" font-weight="700" font-size="76" fill="${LIME}">NEAR is the leash.</text>
    <text x="80" y="520" font-family="${FONT}" font-size="30" fill="#A1A1A6">Keybots · pay, swap and stop scams from any chat · built at NEAR HACKATHON</text>
  </svg>`;
  const r = new Resvg(og, { fitTo: { mode: "width", value: ow }, font: { loadSystemFonts: true, defaultFontFamily: FONT } });
  writeFileSync(join(here, "../public/og.png"), r.render().asPng());
  console.log("wrote ../public/og.png");
}

// A small corner bug with the mark, for the whole recording.
png("bug.png", svg(`${mark(60, 48, 64)}<text x="140" y="94" font-family="${FONT}" font-weight="700" font-size="30" letter-spacing="5" fill="#F5F5F7">KEYBOTS</text>`, false));
