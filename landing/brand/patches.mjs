// Two small patches that paint over the old "AIRKEY" labels on the pay screen (see screens.sh).
//   node landing/brand/patches.mjs  →  brand/out/patch-back.png, brand/out/patch-space.png
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const here = dirname(fileURLToPath(import.meta.url));
const { Resvg } = createRequire(join(here, "../video/package.json"))("@resvg/resvg-js");
const out = join(here, "out");
mkdirSync(out, { recursive: true });
const png = (svg, w) => new Resvg(svg, { fitTo: { mode: "width", value: w }, font: { loadSystemFonts: true, defaultFontFamily: "Helvetica Neue" } }).render().asPng();

// The status-bar back link, top left: "◂ Messages" on black.
writeFileSync(
  join(out, "patch-back.png"),
  png(`<svg xmlns="http://www.w3.org/2000/svg" width="210" height="60"><rect width="210" height="60" fill="#000"/><text x="12" y="42" font-family="Helvetica Neue" font-size="34" fill="#fff">◂ Messages</text></svg>`, 210),
);
// The space bar label: "KEYBOTS", letter-spaced, on the key colour.
writeFileSync(
  join(out, "patch-space.png"),
  png(`<svg xmlns="http://www.w3.org/2000/svg" width="300" height="66"><rect width="300" height="66" fill="#575758"/><text x="150" y="45" text-anchor="middle" font-family="Helvetica Neue" font-size="31" letter-spacing="9" fill="#c7c7cc">KEYBOTS</text></svg>`, 300),
);
// The message field, emptied: the iMessage placeholder on the field colour (for the hero screen).
writeFileSync(
  join(out, "patch-input.png"),
  png(`<svg xmlns="http://www.w3.org/2000/svg" width="420" height="96"><rect width="420" height="96" fill="#3b3b3d"/><text x="14" y="62" font-family="Helvetica Neue" font-size="42" fill="#8e8e93">iMessage</text></svg>`, 420),
);
console.log("wrote patches");
