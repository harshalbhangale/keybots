// Writes public/mark.svg: the mono mascot key, transparent, for the site's nav and footer lockup.
//   node landing/brand/mark.mjs
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { iconArt, setTheme } from "./core.mjs";

const here = dirname(fileURLToPath(import.meta.url));
setTheme("mono");
writeFileSync(join(here, "../public/mark.svg"), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="40 52 160 160">${iconArt()}</svg>`);
console.log("wrote public/mark.svg");
