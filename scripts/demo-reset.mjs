// Puts testnet back to the demo's starting state, in one command:
//
//   npm run demo-reset -- airkey-harshal.testnet
//
// Kill switch off. drain blocked. Nothing waiting for approval. Every
// agent's spend today back to zero (same caps). vendor deleted and made again,
// so it's a new account you've never paid. friend's NEAR back with the owner.
// The leash topped up to LEASH_TOPUP NEAR spendable (default 1.5).
// Testnet only. Run it before each take.
import { actions } from "near-api-js";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { NETWORK, names, near, newKey, saveKey, account, exists, txUrl, fmt, view, provider, KEYS_DIR } from "./common.mjs";

if (NETWORK !== "testnet") throw new Error("demo-reset is for testnet only");
const owner = process.argv[2] ?? "airkey-harshal.testnet";
const n = names(owner);
const o = account(owner);
const GAS = 30_000_000_000_000n;
const TOPUP = near(process.env.LEASH_TOPUP ?? "1.5");
/** The owner keeps this for gas. */
const OWNER_FLOOR = near("0.3");

const ok = (what, res) => console.log(`✓ ${what}${res ? `  ${txUrl(res.transaction.hash)}` : ""}`);
const skip = (what) => console.log(`• ${what}`);
const leash = (methodName, args, deposit = 1n) => o.callFunctionRaw({ contractId: n.leash, methodName, args, deposit, gas: GAS });
const balance = async (id) => BigInt((await provider.viewAccount({ accountId: id, blockQuery: { finality: "final" } })).amount);

// 1. Kill switch off.
if (await view(n.leash, "is_paused")) ok("kill switch off", await leash("set_paused", { paused: false }));
else skip("kill switch is off");

// 2. Nothing waiting for approval.
for (const p of await view(n.leash, "list_pending")) ok(`rejected pending #${p.id} (${fmt(p.amount)} to ${p.receiver})`, await leash("reject", { id: p.id }));

// 3. drain is on the blocklist.
if (await view(n.leash, "blocked_reason", { account: n.drain })) skip(`${n.drain} is blocked`);
else ok(`blocked ${n.drain}`, await leash("block", { account: n.drain, reason: "reported by the Inbox Agent: asked for an urgent payment to unlock an account" }));

// 4. Every agent starts the day at zero, with the same caps.
for (const [agent, a] of await view(n.leash, "list_agents")) {
  if (BigInt(a.spent_today) === 0n) {
    skip(`${agent.length > 40 ? `${agent.slice(0, 8)}…` : agent} has spent nothing today`);
    continue;
  }
  await leash("remove_agent", { agent });
  ok(`${agent.length > 40 ? `${agent.slice(0, 8)}…` : agent} back to 0 spent (caps ${fmt(a.per_payment_cap)} / ${fmt(a.daily_cap)})`,
    await leash("add_agent", { agent, tier: a.tier, per_payment_cap: a.per_payment_cap, daily_cap: a.daily_cap }));
}

// 5. vendor: deleted (its NEAR back to the owner) and made again, so it's new and never paid.
if (await exists(n.vendor)) ok(`deleted ${n.vendor}, its NEAR back to ${owner}`, await account(n.vendor).deleteAccount(owner));
const kp = newKey();
const made = await o.signAndSendTransaction({
  receiverId: n.vendor,
  actions: [actions.createAccount(), actions.transfer(near("0.01")), actions.addFullAccessKey(kp.getPublicKey())],
});
saveKey(n.vendor, kp);
ok(`made ${n.vendor} again (new, never paid)`, made);

// 6. friend's NEAR (what the demo paid it) back to the owner.
if (await exists(n.friend)) {
  const extra = (await balance(n.friend)) - near("0.05");
  if (extra > near("0.01")) ok(`${fmt(extra)} from ${n.friend} back to ${owner}`, await account(n.friend).transfer({ receiverId: owner, amount: extra }));
  else skip(`${n.friend} has nothing extra`);
}

// 7. The leash topped up.
const have = BigInt(await view(n.leash, "available"));
if (have >= TOPUP) skip(`the leash has ${fmt(have)} spendable`);
else {
  const spare = (await balance(owner)) - OWNER_FLOOR;
  const send = TOPUP - have < spare ? TOPUP - have : spare;
  if (send > 0n) ok(`funded the leash with ${fmt(send)} (now about ${fmt(have + send)})`, await o.callFunctionRaw({ contractId: n.leash, methodName: "fund", args: {}, deposit: send, gas: GAS }));
  else console.log(`! ${owner} has no NEAR to spare; the leash has ${fmt(have)}. Get testnet NEAR from a faucet.`);
}

// 8. No price orders left watching. The hosted server by default
// (docs/HOSTING.md), with the token from keys/api-token; AIRKEY_SERVER for another.
const server = process.env.AIRKEY_SERVER ?? "https://13-126-207-245.sslip.io";
let token = process.env.AIRKEY_API_TOKEN ?? "";
try {
  token ||= readFileSync(join(KEYS_DIR, "api-token"), "utf8").trim();
} catch {
  /* no token: a local server without auth */
}
const auth = token ? { authorization: `Bearer ${token}` } : {};
try {
  const { orders } = await (await fetch(`${server}/v1/orders`, { headers: auth, signal: AbortSignal.timeout(5000) })).json();
  for (const x of orders.filter((x) => x.status === "watching")) {
    await fetch(`${server}/v1/orders/${x.id}`, { method: "DELETE", headers: auth });
    ok(`cancelled the order "${x.command}" (when ${x.symbol} is ${x.direction} $${x.price})`);
  }
} catch {
  skip(`couldn't reach ${server} to clear price orders`);
}

console.log(`\nReady:${fmt(await view(n.leash, "available"))} spendable, ${(await view(n.leash, "list_agents")).length} agents, nothing pending.`);
