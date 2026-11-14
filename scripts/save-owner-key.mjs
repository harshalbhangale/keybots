// Saves the owner's NEAR private key to keys/<account>.json (gitignored, 0600)
// without it ever appearing on screen or in chat. Prints only the public key.
//   node save-owner-key.mjs hellbuddy.near
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { KeyPair } from "near-api-js";
import { KEYS_DIR } from "./common.mjs";

const account = process.argv[2] ?? "hellbuddy.near";

function askHidden(prompt) {
  return new Promise((resolve) => {
    process.stdout.write(prompt);
    const stdin = process.stdin;
    stdin.setRawMode?.(true);
    stdin.resume();
    let s = "";
    stdin.on("data", (b) => {
      for (const ch of b.toString("utf8")) {
        if (ch === "\r" || ch === "\n") {
          stdin.setRawMode?.(false);
          stdin.pause();
          process.stdout.write("\n");
          return resolve(s.trim());
        }
        if (ch === "\u0003") process.exit(1); // Ctrl-C
        if (ch === "\u007f") s = s.slice(0, -1); // Backspace
        else s += ch;
      }
    });
  });
}

const secret = await askHidden(`Paste the private key for ${account} (starts with ed25519:, hidden), then Enter: `);
let kp;
try {
  kp = KeyPair.fromString(secret);
} catch {
  console.error("That isn't a NEAR private key (it should start with ed25519:). Nothing was saved.");
  process.exit(1);
}
mkdirSync(KEYS_DIR, { recursive: true });
const file = join(KEYS_DIR, `${account}.json`);
writeFileSync(file, JSON.stringify({ accountId: account, publicKey: kp.getPublicKey().toString(), secretKey: kp.toString() }, null, 2), { mode: 0o600 });
console.log(`Saved to ${file} (only you can read it; never committed).`);
console.log(`Public key: ${kp.getPublicKey().toString()}`);
console.log("Check it's a full-access key on the account at https://nearblocks.io/address/" + account + "#accesskeys");
