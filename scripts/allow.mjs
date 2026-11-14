// Add an account to Spend Limits' allowed list, signed by the owner key in keys/.
//   node scripts/allow.mjs vendor.testnet            (testnet: leash.airkey-harshal.testnet)
//   NEAR_NETWORK=mainnet node scripts/allow.mjs x.near (mainnet: limits.hellbuddy.near)
import { readFileSync } from "node:fs";
import { join } from "node:path";

const account = process.argv[2];
if (!account) throw new Error("Usage: node scripts/allow.mjs <account>");
const mainnet = process.env.NEAR_NETWORK === "mainnet";
const OWNER = mainnet ? "hellbuddy.near" : "airkey-harshal.testnet";
const LIMITS = mainnet ? "limits.hellbuddy.near" : "leash.airkey-harshal.testnet";

const { KEYS_DIR, provider, txUrl } = await import("./common.mjs");
const { Account, actions } = await import("near-api-js");
const sk = JSON.parse(readFileSync(join(KEYS_DIR, `${OWNER}.json`), "utf8")).secretKey;
const owner = new Account(OWNER, provider, sk);

const r = await owner.signAndSendTransaction({
  receiverId: LIMITS,
  actions: [actions.functionCall("allow", { account }, 30_000_000_000_000n, 1n)],
});
const failed = r.status?.Failure ?? r.receipts_outcome.find((o) => o.outcome.status?.Failure)?.outcome.status.Failure;
console.log(`${failed ? "✗ Not allowed" : "✓ Allowed"} ${account} on ${LIMITS}  ${txUrl(r.transaction.hash)}`);
if (failed) console.log(JSON.stringify(failed).slice(0, 300));
