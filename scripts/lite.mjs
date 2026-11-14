// Spend Limits Lite: set it up one step at a time, then check it.
//
//   node lite.mjs --net testnet                 the plan, nothing sent
//   node lite.mjs --net testnet --step 1 --yes  send step 1
//   node lite.mjs --net testnet --check         read the contract
//   node lite.mjs --net testnet --trial --yes   testnet only: one payment per rule
//
// The owner's full-access key must be in keys/<owner>.json. Agents get fresh
// keys (saved to keys/, never printed) that may only call `pay` on the Lite
// contract. The owner's key is also added to the contract account, so it can
// be deleted later and its locked NEAR returned.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const arg = (k) => {
  const i = process.argv.indexOf(k);
  return i > 0 ? process.argv[i + 1] : undefined;
};
const NET = arg("--net") ?? "testnet";
if (!["testnet", "mainnet"].includes(NET)) throw new Error("--net is testnet or mainnet");
process.env.NEAR_NETWORK = NET;
const { KEYS_DIR, provider, near, fmt, view, txUrl, events, returned } = await import("./common.mjs");
const { Account, KeyPair, actions } = await import("near-api-js");

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const WASM = join(ROOT, "contracts/limits-lite/target/wasm32-unknown-unknown/release/spend_limits_lite.wasm");
const OWNER = arg("--owner") ?? (NET === "mainnet" ? "hellbuddy.near" : "airkey-harshal.testnet");
// Testnet already has pay./inbox./trader. for the full contract, so Lite's agents get their own names there.
const P = arg("--prefix") ?? (NET === "mainnet" ? "" : "lt-");
const N = {
  limits: `limits.${OWNER}`,
  pay: `${P}pay.${OWNER}`,
  inbox: `${P}inbox.${OWNER}`,
  trader: `${P}trader.${OWNER}`,
};
const GAS = 30_000_000_000_000n;
/** What the server attaches to pay with Lite (AIRKEY_PAY_TGAS in server/src/near.ts). */
const PAY_GAS = 20_000_000_000_000n; // the server sets AIRKEY_PAY_TGAS=20 for Lite; a pay uses ~4.4 TGas
const ONE_YOCTO = 1n;
// Small on purpose: the whole budget is under 1 NEAR.
const CONTRACT_FUND = "0.6"; // ~0.46 is locked for code and state; the rest is what agents can spend
// NEAR wants a call's balance and key allowance to cover a pessimistic gas bound (~10x the
// real cost): a 20 TGas pay needs ~0.021 NEAR there, though it costs ~0.00044. The owner's
// key goes on every account too, so all of it can be taken back by deleting the account.
const AGENT_FUND = "0.03";
const KEY_ALLOWANCE = near("0.25");
const AGENTS = [
  { id: N.pay, tier: "trusted", per: "0.05", daily: "0.1", what: "Pay Agent: what you type" },
  { id: N.inbox, tier: "untrusted", per: "0.02", daily: "0.05", what: "Inbox Agent: what you paste; allowed list only" },
  { id: N.trader, tier: "trusted", per: "0.05", daily: "0.1", what: "Trading Agent (no swaps on Lite)" },
];

const keyFile = (id) => join(KEYS_DIR, `${id}.json`);
function ownerKey() {
  if (!existsSync(keyFile(OWNER))) throw new Error(`No key for ${OWNER} in ${KEYS_DIR}. Nothing sent.`);
  return JSON.parse(readFileSync(keyFile(OWNER), "utf8"));
}
/** A fresh key for an agent, saved before the transaction that adds it. Never printed. */
function agentKey(id) {
  if (existsSync(keyFile(id))) return KeyPair.fromString(JSON.parse(readFileSync(keyFile(id), "utf8")).secretKey);
  const kp = KeyPair.fromRandom("ed25519");
  mkdirSync(KEYS_DIR, { recursive: true });
  writeFileSync(keyFile(id), JSON.stringify({ accountId: id, publicKey: kp.getPublicKey().toString(), secretKey: kp.toString() }, null, 2), { mode: 0o600 });
  return kp;
}

const steps = [
  {
    n: 1,
    to: N.limits,
    say: `Create ${N.limits} with ${CONTRACT_FUND} NEAR, deploy Spend Limits Lite (45 KB), set ${OWNER} as owner, add ${OWNER}'s key so it can be deleted later`,
    build: () => [
      actions.createAccount(),
      actions.transfer(near(CONTRACT_FUND)),
      actions.addFullAccessKey(KeyPair.fromString(ownerKey().secretKey).getPublicKey()),
      actions.deployContract(readFileSync(WASM)),
      actions.functionCall("new", { owner: OWNER }, GAS, 0n),
    ],
  },
  ...AGENTS.map((a, i) => ({
    n: i + 2,
    to: a.id,
    say: `Create ${a.id} (${a.what}) with ${AGENT_FUND} NEAR for gas, a key that may only call pay on ${N.limits}, and ${OWNER}'s key so it can be deleted and its NEAR returned`,
    build: () => [
      actions.createAccount(),
      actions.transfer(near(AGENT_FUND)),
      actions.addFunctionCallAccessKey(agentKey(a.id).getPublicKey(), N.limits, ["pay"], KEY_ALLOWANCE),
      actions.addFullAccessKey(KeyPair.fromString(ownerKey().secretKey).getPublicKey()),
    ],
  })),
  {
    n: 5,
    to: N.limits,
    say: `Register the agents on ${N.limits}: ${AGENTS.map((a) => `${a.id.split(".")[0]} ${a.per}/${a.daily} NEAR`).join(", ")}`,
    build: () => AGENTS.map((a) => actions.functionCall("add_agent", { agent: a.id, tier: a.tier, per_payment_cap: near(a.per).toString(), daily_cap: near(a.daily).toString() }, GAS, ONE_YOCTO)),
  },
];

const go = process.argv.includes("--yes");
const owner = () => new Account(OWNER, provider, ownerKey().secretKey);

async function send(acct, to, acts, label) {
  const r = await acct.signAndSendTransaction({ receiverId: to, actions: acts });
  const failed = r.status?.Failure ?? r.receipts_outcome.find((o) => o.outcome.status?.Failure)?.outcome.status.Failure;
  const ev = events(r).map((e) => `${e.event}${e.data?.[0]?.rule ? ` ${e.data[0].rule}` : ""}`);
  console.log(`${failed ? "✗" : "✓"} ${label}  ${txUrl(r.transaction.hash)}${ev.length ? `  [${ev.join(", ")}]` : ""}`);
  if (failed) console.log("   ", JSON.stringify(failed).slice(0, 300));
  return { r, failed, value: returned(r) };
}

async function check() {
  const bal = await provider.viewAccount({ accountId: N.limits, blockQuery: { finality: "final" } }).catch(() => null);
  if (!bal) return console.log(`${N.limits} doesn't exist yet.`);
  console.log(`${N.limits}: balance ${fmt(bal.amount)}, storage ${bal.storage_usage} bytes (~${(bal.storage_usage / 100000).toFixed(3)} NEAR locked)`);
  for (const m of ["get_owner", "is_paused", "available", "list_agents", "list_allowed", "list_blocked", "contract_info"]) {
    const v = await view(N.limits, m).catch((e) => `error: ${e.message}`);
    console.log(`  ${m}: ${JSON.stringify(v)}`);
  }
}

if (process.argv.includes("--check")) {
  await check();
} else if (process.argv.includes("--trial")) {
  if (NET !== "testnet") throw new Error("The trial runs on testnet only.");
  if (!go) {
    console.log("Trial on testnet: block drain, pay within limits, over the per-payment limit, a blocked account, the untrusted agent to a stranger, Stop everything, a payment to an account that doesn't exist (spend given back). Add --yes to run it.");
    process.exit(0);
  }
  const o = owner();
  const pay = new Account(N.pay, provider, JSON.parse(readFileSync(keyFile(N.pay), "utf8")).secretKey);
  const inbox = new Account(N.inbox, provider, JSON.parse(readFileSync(keyFile(N.inbox), "utf8")).secretKey);
  const fc = (m, a, d = 0n) => [actions.functionCall(m, a, m === "pay" ? PAY_GAS : GAS, d)];
  const friend = `friend.${OWNER}`;
  await send(o, N.limits, fc("block", { account: `drain.${OWNER}`, reason: "Scam in the trial" }, ONE_YOCTO), "owner blocks drain");
  const t = [
    [pay, { receiver: friend, amount: near("0.01").toString(), memo: "trial" }, "pay 0.01 to friend: paid"],
    [pay, { receiver: friend, amount: near("0.06").toString() }, "pay 0.06: over the 0.05 per-payment limit (R4)"],
    [pay, { receiver: `drain.${OWNER}`, amount: near("0.01").toString() }, "pay drain: blocked list (R3)"],
    [inbox, { receiver: friend, amount: near("0.01").toString() }, "inbox pays friend, not on the allowed list (R6)"],
    [pay, { receiver: `nobody-${Date.now()}.${OWNER}`, amount: near("0.01").toString() }, "pay an account that doesn't exist: spend given back"],
  ];
  for (const [a, args, label] of t) {
    const { value } = await send(a, N.limits, fc("pay", args), label);
    console.log("   ", JSON.stringify(value));
  }
  await send(o, N.limits, fc("set_paused", { paused: true }, ONE_YOCTO), "owner: Stop everything");
  const { value } = await send(pay, N.limits, fc("pay", { receiver: friend, amount: near("0.01").toString() }), "pay while stopped (R1)");
  console.log("   ", JSON.stringify(value));
  await send(o, N.limits, fc("set_paused", { paused: false }, ONE_YOCTO), "owner: let agents spend again");
  await check();
} else {
  const only = Number(arg("--step"));
  console.log(`Spend Limits Lite on ${NET}, owner ${OWNER}${go ? "" : " (plan only, nothing sent)"}\n`);
  for (const s of steps) {
    if (only && s.n !== only) continue;
    console.log(`${s.n}. ${OWNER} -> ${s.to}: ${s.say}`);
    if (go && only) await send(owner(), s.to, s.build(), `step ${s.n}`);
  }
  if (go && !only) console.log("\nSend one step at a time: --step N --yes");
}
