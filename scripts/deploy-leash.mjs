// Redeploy the leash code (state is kept). npm run deploy -- airkey-<yourname>.testnet
import { readFileSync } from "node:fs";
import { names, account, WASM, txUrl } from "./common.mjs";

const owner = process.argv[2];
if (!owner) {
  console.error("Usage: npm run deploy -- airkey-<yourname>.testnet");
  process.exit(1);
}
const { leash } = names(owner);
const res = await account(leash).deployContract(readFileSync(WASM));
console.log(`✓ deployed ${leash}  ${txUrl(res.transaction.hash)}`);
