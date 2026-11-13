// Moves the agents' signing keys into OutLayer agent custody (testnet only).
//
//   node setup-outlayer.mjs airkey-<yourname>.testnet [--register] [--policy]
//
// For each agent (pay, inbox, trader) it:
//   1. uses the agent's OutLayer wallet key from server/.env (OUTLAYER_KEY_TRUSTED,
//      _UNTRUSTED, _TRADE), or with --register creates the wallet at OutLayer and
//      writes the new key there. The key is never printed.
//   2. reads the wallet's NEAR implicit account from OutLayer,
//   3. sends it 0.3 NEAR for gas from the owner, if it has less than 0.2,
//   4. registers it on the leash with add_agent, with the same tier and caps as
//      the agent it replaces,
//   5. writes AIRKEY_AGENT_* and AIRKEY_SIGNER=outlayer to server/.env.
// With --policy it also stores an OutLayer policy on each wallet that only lets
// it call the leash (a second lock, next to the leash's own rules).
//
// The old agents (pay.<owner> etc.) stay on the leash; remove them by hand if wanted.
import { actions } from "near-api-js";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { ROOT, NETWORK, names, near, fmt, account, provider, txUrl, view } from "./common.mjs";

const API = (process.env.OUTLAYER_API ?? "https://testnet-api.outlayer.ai").replace(/\/$/, "");
const ENV_FILE = join(ROOT, "server", ".env");
const GAS_FLOOR = near(0.2);
const GAS_TOPUP = near(0.3);

const args = process.argv.slice(2);
const owner = args.find((a) => !a.startsWith("--"));
const REGISTER = args.includes("--register");
const POLICY = args.includes("--policy");
if (!owner || NETWORK !== "testnet" || !owner.endsWith(".testnet") || !API.includes("testnet")) {
  console.error("Usage: node setup-outlayer.mjs airkey-<yourname>.testnet [--register] [--policy]   (testnet only)");
  process.exit(1);
}
const n = names(owner);
const o = account(owner);

// ---------- server/.env (gitignored) ----------
function readEnv() {
  const env = {};
  if (!existsSync(ENV_FILE)) return env;
  for (const line of readFileSync(ENV_FILE, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) env[m[1]] = m[2];
  }
  return env;
}
function setEnv(updates) {
  const lines = existsSync(ENV_FILE) ? readFileSync(ENV_FILE, "utf8").split("\n") : [];
  const left = { ...updates };
  const out = lines.map((line) => {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=/);
    if (m && m[1] in left) {
      const v = left[m[1]];
      delete left[m[1]];
      return `${m[1]}=${v}`;
    }
    return line;
  });
  while (out.length && out[out.length - 1] === "") out.pop();
  for (const [k, v] of Object.entries(left)) out.push(`${k}=${v}`);
  writeFileSync(ENV_FILE, out.join("\n") + "\n", { mode: 0o600 });
}

// ---------- OutLayer ----------
async function outlayer(method, path, key, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { ...(key ? { authorization: `Bearer ${key}` } : {}), "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(`OutLayer ${method} ${path}: ${res.status} ${json.error ?? ""} ${json.message ?? ""}`);
  return json;
}

async function balance(accountId) {
  try {
    const a = await provider.viewAccount({ accountId, blockQuery: { finality: "final" } });
    return BigInt(a.amount);
  } catch {
    return 0n;
  }
}

const AGENTS = [
  { role: "TRUSTED", replaces: n.pay },
  { role: "UNTRUSTED", replaces: n.inbox },
  { role: "TRADE", replaces: n.trade },
];
const current = new Map(await view(n.leash, "list_agents"));
const env = readEnv();
const updates = {};

for (const { role, replaces } of AGENTS) {
  const keyName = `OUTLAYER_KEY_${role}`;
  let key = env[keyName];
  if (!key) {
    if (!REGISTER) {
      console.error(`✗ ${keyName} is not in server/.env. Rerun with --register to create the wallet at OutLayer.`);
      process.exit(1);
    }
    const r = await outlayer("POST", "/register", null, {});
    if (!r.api_key?.startsWith("wk_")) throw new Error("OutLayer /register returned no wk_ key");
    key = r.api_key;
    setEnv({ [keyName]: key }); // saved at once: OutLayer shows it only this one time
    console.log(`✓ ${role}: registered OutLayer wallet ${r.wallet_id}`);
  }

  const addr = await outlayer("GET", "/wallet/v1/address?chain=near", key);
  const agent = addr.address;
  console.log(`• ${role}: OutLayer NEAR account ${agent} (key ${addr.public_key})`);

  const have = await balance(agent);
  if (have < GAS_FLOOR) {
    const res = await o.signAndSendTransaction({ receiverId: agent, actions: [actions.transfer(GAS_TOPUP)] });
    console.log(`✓ ${role}: sent ${fmt(GAS_TOPUP)} for gas  ${txUrl(res.transaction.hash)}`);
  } else {
    console.log(`• ${role}: has ${fmt(have)}, no top-up`);
  }

  const was = current.get(replaces);
  const caps = was
    ? { tier: was.tier, per_payment_cap: was.per_payment_cap, daily_cap: was.daily_cap }
    : { tier: role === "UNTRUSTED" ? "untrusted" : "trusted", per_payment_cap: near(0.5).toString(), daily_cap: near(1).toString() };
  const res = await o.callFunctionRaw({ contractId: n.leash, methodName: "add_agent", args: { agent, ...caps }, deposit: 1n });
  console.log(`✓ ${role}: on the leash as ${caps.tier}, ${fmt(caps.per_payment_cap)} a payment, ${fmt(caps.daily_cap)} a day  ${txUrl(res.transaction.hash)}`);

  updates[`AIRKEY_AGENT_${role}`] = agent;

  if (POLICY) await storePolicy(role, key, addr);
}

setEnv({ ...updates, AIRKEY_SIGNER: "outlayer", OUTLAYER_API: API });
console.log(`✓ server/.env: AIRKEY_SIGNER=outlayer and the three agent accounts (keys not shown)`);

// ---------- optional second lock: an OutLayer policy ----------
// Only `call`, only to the leash. The keystore then refuses to sign anything
// else for this wallet, e.g. a transfer of its gas money.
async function storePolicy(role, key, addr) {
  const enc = await outlayer("POST", "/wallet/v1/encrypt-policy", key, {
    wallet_id: addr.wallet_id,
    rules: { transaction_types: ["call"], addresses: { mode: "whitelist", list: [n.leash] } },
  });
  const signed = await outlayer("POST", "/wallet/v1/sign-policy", key, { encrypted_data: enc.encrypted_base64, caller: owner });
  if (signed.status) throw new Error(`OutLayer policy for ${role} is waiting for approval (${signed.approval_id})`);
  const contract = process.env.OUTLAYER_CONTRACT ?? "outlayer.testnet";
  const res = await o.callFunctionRaw({
    contractId: contract,
    methodName: "store_wallet_policy",
    args: {
      wallet_pubkey: enc.wallet_pubkey,
      encrypted_data: enc.encrypted_base64,
      wallet_signature: signed.signature_hex,
      version: signed.version,
      locked: signed.locked,
      valid_until: signed.valid_until,
    },
    deposit: near(Number(process.env.OUTLAYER_POLICY_DEPOSIT ?? "0.1")),
  });
  console.log(`✓ ${role}: OutLayer policy stored (call -> ${n.leash} only)  ${txUrl(res.transaction.hash)}`);
}
