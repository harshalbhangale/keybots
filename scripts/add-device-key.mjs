// Enroll a phone: add its public key to the owner account as a full-access key.
// The AIRKEY app shows the key in Settings ("This device"). Testnet only.
//
//   npm run add-device -- airkey-<yourname>.testnet ed25519:<key from the app>
import { PublicKey, actions } from "near-api-js";
import { NETWORK, account, provider, txUrl } from "./common.mjs";

const [owner, publicKey] = process.argv.slice(2);
if (!owner || !publicKey?.startsWith("ed25519:")) {
  console.error("Usage: npm run add-device -- airkey-<yourname>.testnet ed25519:<key from the app>");
  process.exit(1);
}
if (NETWORK !== "testnet") {
  console.error("Testnet only. On mainnet, add the device key from your own wallet.");
  process.exit(1);
}

try {
  await provider.viewAccessKey({ accountId: owner, publicKey, finalityQuery: { finality: "final" } });
  console.log(`• ${publicKey} is already on ${owner}`);
  process.exit(0);
} catch {
  /* not there yet */
}

const res = await account(owner).signAndSendTransaction({ receiverId: owner, actions: [actions.addFullAccessKey(PublicKey.fromString(publicKey))] });
console.log(`✓ added the device key to ${owner}  ${txUrl(res.transaction.hash)}`);
