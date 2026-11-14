// Writes every Keybots brand asset from the one mascot drawing (core.mjs), in the mono theme.
//   node landing/brand/assets.mjs
// → landing/public/{logo,favicon}.svg, ios/AirKey/Assets.xcassets/AppIcon…, ios/Shared/Mascot.xcassets/…, out/*
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { iconArt, scene, setTheme } from "./core.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const { Resvg } = createRequire(join(here, "../video/package.json"))("@resvg/resvg-js");
const png = (svg, w) => new Resvg(svg, { fitTo: { mode: "width", value: w } }).render().asPng();
setTheme("mono");

const BG = "#0E0F13";
const tileDefs = `<defs><radialGradient id="g" cx="50%" cy="45%" r="60%"><stop offset="0" stop-color="#C6F25A" stop-opacity=".16"/><stop offset="1" stop-color="#C6F25A" stop-opacity="0"/></radialGradient></defs>`;
const wrap = (vb, inner) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}">${inner}</svg>`;

// 1. The cropped, transparent mark: the key on its switch.
const MARK_VB = "40 52 160 160";
const mark = wrap(MARK_VB, iconArt());
// 2. The full-bleed app icon (opaque square: iOS rounds the corners itself).
const appIcon = wrap("0 0 240 240", `${tileDefs}<rect width="240" height="240" fill="${BG}"/><rect width="240" height="240" fill="url(#g)"/>${iconArt()}`);
// 3. The favicon: the icon on a rounded dark tile.
const favicon = wrap("0 0 240 240", `${tileDefs}<rect width="240" height="240" rx="54" fill="${BG}"/><rect width="240" height="240" rx="54" fill="url(#g)"/>${iconArt()}`);

writeFileSync(join(root, "public/logo.svg"), mark);
writeFileSync(join(root, "public/favicon.svg"), favicon);

const out = join(here, "out");
mkdirSync(out, { recursive: true });
writeFileSync(join(out, "icon.png"), png(appIcon, 1024));
writeFileSync(join(out, "mark.png"), png(mark, 540));
writeFileSync(join(out, "mascot-click.png"), png(wrap("0 0 240 240", `${tileDefs}<rect width="240" height="240" fill="${BG}"/><rect width="240" height="240" fill="url(#g)"/>${scene(0.62)}`), 1024));

// iOS: the app icon (flattened to RGB by make-ios.sh) and the brand-key image, 1x/2x/3x.
const ios = join(root, "../ios");
const iconDir = join(ios, "AirKey/Assets.xcassets/AppIcon.appiconset");
const markDir = join(ios, "Shared/Mascot.xcassets/MascotMark.imageset");
mkdirSync(markDir, { recursive: true });
writeFileSync(join(iconDir, "AppIcon-alpha.png"), png(appIcon, 1024));
[1, 2, 3].forEach((k) => writeFileSync(join(markDir, `MascotMark@${k}x.png`), png(mark, 28 * k * 2)));
writeFileSync(
  join(markDir, "Contents.json"),
  JSON.stringify(
    {
      images: [1, 2, 3].map((k) => ({ idiom: "universal", filename: `MascotMark@${k}x.png`, scale: `${k}x` })),
      info: { author: "xcode", version: 1 },
    },
    null,
    2,
  ),
);
writeFileSync(join(ios, "Shared/Mascot.xcassets/Contents.json"), JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2));
console.log("brand assets written");
