// A fresh key for hellbuddy.near, for scripts/setup-mainnet.mjs to sign with.
//
//   npm run new-owner-key
//
// Saves it to keys/hellbuddy.near.json (gitignored, readable only by you) and
// prints only the public key and how to add it to hellbuddy.near from your own
// wallet. Nothing is sent: the key does nothing until you add it.
// Remove it from the account once setup is done.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { KeyPair } from "near-api-js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const KEYS_DIR = process.env.AIRKEY_KEYS_DIR ?? join(ROOT, "keys");
const OWNER = process.argv[2] ?? "hellbuddy.near";
const file = join(KEYS_DIR, `${OWNER}.json`);

if (existsSync(file)) {
  console.error(`${file} already exists. Delete it yourself first if you really want a new key.`);
  process.exit(1);
}
const kp = KeyPair.fromRandom("ed25519");
const publicKey = kp.getPublicKey().toString();
mkdirSync(KEYS_DIR, { recursive: true });
writeFileSync(file, JSON.stringify({ accountId: OWNER, publicKey, secretKey: kp.toString() }, null, 2), { mode: 0o600 });

console.log(`Saved a new key for ${OWNER} to ${file} (only you can read it; keys/ is never committed).

Public key:
  ${publicKey}

Add it to ${OWNER} as a full-access key, from your own wallet. With NEAR CLI (near-cli-rs):

  near account add-key ${OWNER} grant-full-access use-manually-provided-public-key ${publicKey} network-config mainnet

The CLI then asks how you sign (seed phrase, Ledger or your keychain) and shows the transaction before sending.
It costs a tiny gas fee and about 0.0004 NEAR of storage.

Then check the plan: npm run setup-mainnet
When setup is done, delete this key from ${OWNER}:
  near account delete-keys ${OWNER} public-keys ${publicKey} network-config mainnet`);
