// Spend Limits on NEAR mainnet, under hellbuddy.near. Real money.
//
//   npm run setup-mainnet                    dry run: reads the chain, prints every step and the total. Signs nothing.
//   npm run setup-mainnet -- --fund 0.5      the same, with another amount for Spend Limits to hold
//   npm run setup-mainnet -- --yes --step 1  signs and sends step 1 only, after printing it again
//
// One step at a time, on purpose: the owner reads each step (signer, receiver,
// method, deposit, gas) and approves it before it is sent. A step the chain
// shows as done is skipped.
//
// The owner's key is read from keys/hellbuddy.near.json (npm run new-owner-key
// makes one; the owner adds its public key to hellbuddy.near from their own
// wallet). Each new account's key is made fresh, saved to keys/ (gitignored,
// 0600) and never printed.
import { existsSync, readFileSync, statSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describeStep, fmtNear, mainnetPlan, mainnetNames, MAINNET_AGENTS, USDC_MAINNET, USDT_MAINNET, WRAP_MAINNET } from "./mainnet-plan.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const KEYS_DIR = process.env.AIRKEY_KEYS_DIR ?? join(ROOT, "keys");
const WASM = join(ROOT, "contracts/leash/target/near/airkey_leash.wasm");
const RPC = process.env.NEAR_MAINNET_RPC ?? "https://rpc.mainnet.near.org";
const EXPLORER = "https://nearblocks.io";

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : fallback;
};
const OWNER = flag("owner", "hellbuddy.near");
const FUND = flag("fund", "0.5");
const YES = argv.includes("--yes");
const STEP = flag("step");
if (!OWNER.endsWith(".near")) {
  console.error("This script is for NEAR mainnet: the owner must be a .near account.");
  process.exit(1);
}
if (!/^\d+(\.\d+)?$/.test(FUND)) {
  console.error(`--fund takes an amount of NEAR, like 0.5 (got ${FUND}).`);
  process.exit(1);
}

// ---------- read-only chain access (public RPC) ----------

async function rpc(method, params) {
  const r = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: "airkey", method, params }),
    signal: AbortSignal.timeout(15_000),
  });
  return r.json();
}
async function viewAccount(id) {
  const j = await rpc("query", { request_type: "view_account", finality: "final", account_id: id });
  return j.result ?? null;
}
async function view(contract, method, args = {}) {
  const j = await rpc("query", { request_type: "call_function", finality: "final", account_id: contract, method_name: method, args_base64: Buffer.from(JSON.stringify(args)).toString("base64") });
  if (!j.result?.result) return undefined;
  return JSON.parse(Buffer.from(j.result.result).toString() || "null");
}
async function accessKey(id, publicKey) {
  const j = await rpc("query", { request_type: "view_access_key", finality: "final", account_id: id, public_key: publicKey });
  return j.result ?? null;
}

// ---------- read the chain, make the plan ----------

if (!existsSync(WASM)) {
  console.error(`No contract build at ${WASM}. Build it first: cd contracts/leash && cargo near build non-reproducible-wasm`);
  process.exit(1);
}
const wasmBytes = statSync(WASM).size;
const n = mainnetNames(OWNER);

console.log(`Spend Limits on NEAR mainnet, read from ${RPC}${YES ? "" : " (dry run: nothing is signed)"}\n`);
const [owner, limits, gas, ...rest] = await Promise.all([
  viewAccount(OWNER),
  viewAccount(n.limits),
  rpc("gas_price", [null]),
  ...MAINNET_AGENTS.map((a) => viewAccount(n[a.key])),
]);
const agentsExist = Object.fromEntries(MAINNET_AGENTS.map((a, i) => [a.key, !!rest[i]]));
const tokens = [WRAP_MAINNET, USDC_MAINNET, USDT_MAINNET];
const bounds = await Promise.all(tokens.map((t) => view(t, "storage_balance_bounds").catch(() => undefined)));
const storage = Object.fromEntries(tokens.map((t, i) => [t, bounds[i]?.min ?? "1250000000000000000000"]));

const done = { limits: false, agents: false, fund: false, "token-rules": false };
for (const a of MAINNET_AGENTS) done[a.key] = agentsExist[a.key];
let registered = [];
if (limits) {
  const ownerOnChain = await view(n.limits, "get_owner").catch(() => undefined);
  done.limits = ownerOnChain === OWNER;
  if (ownerOnChain && ownerOnChain !== OWNER) {
    console.error(`! ${n.limits} already runs a contract owned by ${ownerOnChain}. Stop and check.`);
    process.exit(1);
  }
  registered = await Promise.all(MAINNET_AGENTS.map((a) => view(n.limits, "get_agent", { agent: n[a.key] }).catch(() => null)));
  done.agents = registered.every(Boolean);
  const regs = await Promise.all(tokens.map((t) => view(t, "storage_balance_of", { account_id: n.limits }).catch(() => null)));
  done["storage-wNEAR"] = !!regs[0];
  done["storage-USDC"] = !!regs[1];
  done["storage-USDT"] = !!regs[2];
  const caps = await Promise.all([USDC_MAINNET, USDT_MAINNET].map((t) => view(n.limits, "get_token_cap", { token: t }).catch(() => null)));
  done["token-rules"] = caps.every(Boolean);
}

const plan = mainnetPlan({ owner: OWNER, wasmBytes, fund: FUND, storage, done, gasPrice: gas?.result?.gas_price });

console.log("What the chain says now:");
console.log(`  ${OWNER}: ${owner ? `exists, ${fmtNear(owner.amount)} NEAR (${fmtNear(BigInt(owner.storage_usage) * 10n ** 19n)} of it held for its own storage)` : "DOES NOT EXIST on mainnet"}`);
console.log(`  ${n.limits}: ${limits ? `exists, ${fmtNear(limits.amount)} NEAR${done.limits ? ", Spend Limits running" : ""}` : "doesn't exist yet"}`);
for (const a of MAINNET_AGENTS) console.log(`  ${n[a.key]}: ${agentsExist[a.key] ? "exists" : "doesn't exist yet"}`);
console.log(`  gas price: ${gas?.result?.gas_price ?? "unknown"} yoctoNEAR a unit (1 TGas ≈ ${gas?.result?.gas_price ? fmtNear(BigInt(gas.result.gas_price) * 10n ** 12n, 5) : "0.0001"} NEAR)`);
console.log(`  contract code: ${wasmBytes} bytes, so ${fmtNear(plan.codeStorage)} NEAR of storage at 1 NEAR per 100 KB`);
console.log("  contacts: none on mainnet (the address book stays empty until the owner names real accounts they control)\n");

for (const s of plan.steps) console.log(describeStep(s) + "\n");

const spendable = owner ? BigInt(owner.amount) - BigInt(owner.storage_usage) * 10n ** 19n : 0n;
console.log(`Total NEAR needed from ${OWNER} for the steps not done yet: ${fmtNear(plan.total)} NEAR (deposits + the most gas can cost).`);
if (owner) {
  console.log(spendable >= plan.total ? `  ${OWNER} has ${fmtNear(spendable)} NEAR free: enough.` : `  ${OWNER} has ${fmtNear(spendable)} NEAR free: ${fmtNear(plan.total - spendable)} NEAR short. Top it up first.`);
}
console.log(`  Of that, ${fmtNear(plan.steps.find((s) => s.id === "fund").deposit + plan.steps.find((s) => s.id === "limits").deposit - plan.codeStorage)} NEAR sits in Spend Limits for the agents to spend; the owner can take it back with withdraw.`);

if (!YES) {
  console.log("\nDry run: nothing was signed. To send one step: npm run setup-mainnet -- --yes --step <number>");
  process.exit(0);
}

// ---------- sign one step ----------

const step = plan.steps.find((s) => String(s.n) === String(STEP));
if (!step) {
  console.error(`\n--yes needs --step <number>, one of ${plan.steps.map((s) => s.n).join(", ")}. One step at a time.`);
  process.exit(1);
}
if (step.done) {
  console.log(`\nStep ${step.n} is already done on chain. Nothing sent.`);
  process.exit(0);
}
if (!owner) {
  console.error(`\n${OWNER} doesn't exist on mainnet. Nothing sent.`);
  process.exit(1);
}
const firstOpen = plan.steps.find((s) => !s.done && !s.optional);
if (firstOpen && step.n > firstOpen.n && !step.optional) {
  console.error(`\nStep ${firstOpen.n} isn't done yet. Run the steps in order. Nothing sent.`);
  process.exit(1);
}
const keyFile = join(KEYS_DIR, `${OWNER}.json`);
if (!existsSync(keyFile)) {
  console.error(`\nNo owner key at ${keyFile}. Run npm run new-owner-key, add the key from your wallet, then try again. Nothing sent.`);
  process.exit(1);
}
const ownerKey = JSON.parse(readFileSync(keyFile, "utf8"));
if (ownerKey.accountId !== OWNER) {
  console.error(`\n${keyFile} is for ${ownerKey.accountId}, not ${OWNER}. Nothing sent.`);
  process.exit(1);
}
const onChain = await accessKey(OWNER, ownerKey.publicKey);
if (onChain?.permission !== "FullAccess") {
  console.error(`\nThe key in ${keyFile} isn't a full-access key of ${OWNER} on mainnet yet. Add it from your wallet first. Nothing sent.`);
  process.exit(1);
}

const { Account, JsonRpcProvider, KeyPair, actions } = await import("near-api-js");
const provider = new JsonRpcProvider({ url: RPC });
const signer = new Account(OWNER, provider, ownerKey.secretKey);

/** A fresh key for a new account, saved to keys/ before the transaction that adds it. Never printed. */
function freshKey(accountId) {
  const p = join(KEYS_DIR, `${accountId}.json`);
  if (existsSync(p)) return KeyPair.fromString(JSON.parse(readFileSync(p, "utf8")).secretKey);
  const kp = KeyPair.fromRandom("ed25519");
  mkdirSync(KEYS_DIR, { recursive: true });
  writeFileSync(p, JSON.stringify({ accountId, publicKey: kp.getPublicKey().toString(), secretKey: kp.toString() }, null, 2), { mode: 0o600 });
  return kp;
}

const built = step.actions.map((a) => {
  switch (a.action) {
    case "CreateAccount":
      return actions.createAccount();
    case "Transfer":
      return actions.transfer(a.deposit);
    case "AddKey": {
      const kp = freshKey(step.receiver);
      return a.methods ? actions.addFunctionCallAccessKey(kp.getPublicKey(), n.limits, a.methods, a.allowance) : actions.addFullAccessKey(kp.getPublicKey());
    }
    case "DeployContract":
      return actions.deployContract(readFileSync(WASM));
    case "FunctionCall":
      return actions.functionCall(a.method, a.args, a.gas, a.deposit);
    default:
      throw new Error(`Unknown action ${a.action}`);
  }
});

console.log(`\nSending step ${step.n} now, as ${OWNER}:\n${describeStep(step)}`);
const res = await signer.signAndSendTransaction({ receiverId: step.receiver, actions: built });
const failed = res.status?.Failure;
console.log(failed ? `\n✗ Step ${step.n} failed: ${JSON.stringify(failed)}` : `\n✓ Step ${step.n} done.`);
console.log(`  ${EXPLORER}/txns/${res.transaction.hash}`);
process.exit(failed ? 1 : 0);
