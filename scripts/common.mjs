// Shared helpers for the AirKey testnet scripts.
import { Account, JsonRpcProvider, KeyPair, nearToYocto, yoctoToNear } from "near-api-js";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
export const KEYS_DIR = join(ROOT, "keys"); // gitignored
export const NETWORK = process.env.NEAR_NETWORK ?? "testnet";
export const RPC = process.env.NEAR_RPC ?? (NETWORK === "mainnet" ? "https://free.rpc.fastnear.com" : "https://test.rpc.fastnear.com");
export const EXPLORER = NETWORK === "mainnet" ? "https://nearblocks.io" : "https://testnet.nearblocks.io";
export const WASM = join(ROOT, "contracts/leash/target/near/airkey_leash.wasm");

export const provider = new JsonRpcProvider({ url: RPC });
export const near = (n) => nearToYocto(String(n));
export const fmt = (y) => `${yoctoToNear(BigInt(y), 4)} NEAR`;

/** The deployment's account names, all under the owner. */
export function names(owner) {
  return {
    owner,
    leash: `leash.${owner}`,
    pay: `pay.${owner}`, // trusted agent: acts on what the owner types
    inbox: `inbox.${owner}`, // untrusted agent: acts on pasted or inbound text
    friend: `friend.${owner}`, // demo receiver on the allowlist
    vendor: `vendor.${owner}`, // demo receiver not on the allowlist
    drain: `drain.${owner}`, // demo scammer
  };
}

export function saveKey(accountId, keyPair) {
  mkdirSync(KEYS_DIR, { recursive: true });
  writeFileSync(join(KEYS_DIR, `${accountId}.json`), JSON.stringify({ accountId, publicKey: keyPair.getPublicKey().toString(), secretKey: keyPair.toString() }, null, 2), { mode: 0o600 });
}

export function loadKey(accountId) {
  const p = join(KEYS_DIR, `${accountId}.json`);
  if (!existsSync(p)) throw new Error(`No key for ${accountId} in keys/. Run npm run setup first.`);
  return JSON.parse(readFileSync(p, "utf8")).secretKey;
}

export function account(accountId) {
  return new Account(accountId, provider, loadKey(accountId));
}

export function newKey() {
  return KeyPair.fromRandom("ed25519");
}

export async function exists(accountId) {
  try {
    await provider.viewAccount({ accountId, blockQuery: { finality: "final" } });
    return true;
  } catch {
    return false;
  }
}

export async function view(contractId, method, args = {}) {
  return provider.callFunction({ contractId, method, args, blockQuery: { finality: "optimistic" } });
}

export const txUrl = (hash) => `${EXPLORER}/txns/${hash}`;

/** The leash's NEP-297 events in a transaction outcome. */
export function events(outcome) {
  const logs = [outcome.transaction_outcome, ...(outcome.receipts_outcome ?? [])].flatMap((o) => o?.outcome?.logs ?? []);
  return logs.filter((l) => l.startsWith("EVENT_JSON:")).map((l) => JSON.parse(l.slice("EVENT_JSON:".length)));
}

/** The return value of the first function call in a transaction outcome. */
export function returned(outcome) {
  const v = outcome.status?.SuccessValue;
  if (!v) return undefined;
  const s = Buffer.from(v, "base64").toString();
  try {
    return JSON.parse(s);
  } catch {
    return s;
  }
}
