// One-time testnet setup. Run it yourself: it creates NEAR testnet accounts.
//
//   npm run setup -- airkey-<yourname>.testnet
//
// 1. Creates the owner account through the testnet faucet (it arrives with free testnet NEAR).
// 2. Creates the sub-accounts: leash (the contract), pay, inbox and trade (the agents, whose only key is a
//    function-call key for the leash), and friend / vendor / drain (demo receivers).
// 3. Deploys and initialises the leash, registers the agents, allowlists friend, funds the leash.
// Keys are saved to keys/ (gitignored).
import { readFileSync } from "node:fs";
import { actions } from "near-api-js";
import { NETWORK, WASM, names, near, newKey, saveKey, account, exists, txUrl, fmt, view } from "./common.mjs";

const FAUCET = process.env.NEAR_FAUCET ?? "https://helper.nearprotocol.com/account";
const owner = process.argv[2];
if (!owner || !owner.endsWith(".testnet") || NETWORK !== "testnet") {
  console.error("Usage: npm run setup -- airkey-<yourname>.testnet   (testnet only)");
  process.exit(1);
}
const n = names(owner);

async function createOwner() {
  if (await exists(owner)) {
    console.log(`• ${owner} already exists; using the key in keys/.`);
    return;
  }
  const kp = newKey();
  const res = await fetch(FAUCET, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ newAccountId: owner, newAccountPublicKey: kp.getPublicKey().toString() }),
  });
  if (!res.ok) {
    throw new Error(`Faucet said ${res.status}: ${(await res.text()).slice(0, 200)}\n` +
      `Fallback: create ${owner} in a testnet wallet, then save {accountId, secretKey} to keys/${owner}.json and rerun.`);
  }
  saveKey(owner, kp);
  for (let i = 0; i < 20 && !(await exists(owner)); i++) await new Promise((r) => setTimeout(r, 1500));
  console.log(`✓ created ${owner} through the faucet`);
}

async function createSub(ownerAcc, id, initial, key) {
  if (await exists(id)) return console.log(`• ${id} already exists`);
  const res = await ownerAcc.signAndSendTransaction({ receiverId: id, actions: [actions.createAccount(), actions.transfer(initial), key] });
  console.log(`✓ created ${id}  ${txUrl(res.transaction.hash)}`);
}

await createOwner();
const o = account(owner);

// The leash account gets its own full-access key (needed to deploy; can be deleted later to lock the code).
const leashKey = newKey();
if (!(await exists(n.leash))) saveKey(n.leash, leashKey);
await createSub(o, n.leash, near(4), actions.addFullAccessKey(leashKey.getPublicKey()));

// Agents: the only key is a function-call key for the leash's pay/report, with a 0.25 NEAR gas allowance.
for (const id of [n.pay, n.inbox, n.trade]) {
  const kp = newKey();
  if (!(await exists(id))) saveKey(id, kp);
  await createSub(o, id, near(0.3), actions.addFunctionCallAccessKey(kp.getPublicKey(), n.leash, ["pay", "report"], near(0.25)));
}

// Demo receivers (keys kept so they can be inspected or cleaned up).
for (const id of [n.friend, n.vendor, n.drain]) {
  const kp = newKey();
  if (!(await exists(id))) saveKey(id, kp);
  await createSub(o, id, near(0.01), actions.addFullAccessKey(kp.getPublicKey()));
}

// Deploy + init the leash.
const leash = account(n.leash);
const code = readFileSync(WASM);
let initialised = true;
try { await view(n.leash, "get_owner"); } catch { initialised = false; }
if (!initialised) {
  const res = await leash.signAndSendTransaction({
    receiverId: n.leash,
    actions: [actions.deployContract(code), actions.functionCall("new", { owner }, 30_000_000_000_000n, 0n)],
  });
  console.log(`✓ deployed and initialised ${n.leash}  ${txUrl(res.transaction.hash)}`);
} else {
  console.log(`• ${n.leash} already initialised (use npm run deploy to update code)`);
}

// Rules: pay = trusted, inbox = untrusted, both 0.5 per payment / 1 a day. trade = trusted, 1 a trade / 2 a day.
// friend is allowlisted.
const call = (methodName, args) => o.callFunction({ contractId: n.leash, methodName, args, deposit: 1n });
await call("add_agent", { agent: n.pay, tier: "trusted", per_payment_cap: near(0.5).toString(), daily_cap: near(1).toString() });
await call("add_agent", { agent: n.inbox, tier: "untrusted", per_payment_cap: near(0.5).toString(), daily_cap: near(1).toString() });
await call("add_agent", { agent: n.trade, tier: "trusted", per_payment_cap: near(1).toString(), daily_cap: near(2).toString() });
await call("allow", { account: n.friend });
console.log("✓ agents registered (pay, inbox, trade), friend allowlisted");

console.log(`\nLeash can spend ${fmt(await view(n.leash, "available"))}. Explorer: ${txUrl("").replace("/txns/", "/address/")}${n.leash}`);
console.log(`Next: npm run e2e -- ${owner}`);
