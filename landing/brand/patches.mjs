// Two small patches that paint over the old "AIRKEY" labels on the pay screen (see screens.sh).
//   node landing/brand/patches.mjs  →  brand/out/patch-back.png, brand/out/patch-space.png
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
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
// The hero's Siri Suggestions row: the Keybots app icon in Reminders' place (iOS rounded
// square, the same 209 px as its neighbours) and its label "Keybots" on the row's background.
const icon = readFileSync(join(here, "keybots-icon-1024.png")).toString("base64");
writeFileSync(
  join(out, "patch-icon.png"),
  png(
    `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="209" height="209"><defs><clipPath id="m"><rect width="209" height="209" rx="47"/></clipPath></defs><image clip-path="url(#m)" width="209" height="209" xlink:href="data:image/png;base64,${icon}"/></svg>`,
    209,
  ),
);
writeFileSync(
  join(out, "patch-label.png"),
  png(
    `<svg xmlns="http://www.w3.org/2000/svg" width="224" height="58"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#363542"/><stop offset="1" stop-color="#3b3e4f"/></linearGradient></defs><rect width="224" height="58" fill="url(#g)"/><text x="112" y="40" text-anchor="middle" font-family="Helvetica Neue" font-size="36" fill="#ffffff">Keybots</text></svg>`,
    224,
  ),
);
console.log("wrote patches");
