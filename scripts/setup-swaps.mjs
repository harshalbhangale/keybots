// Gets a testnet deployment ready for real swaps on Rhea (testnet only).
//
//   npm run setup-swaps -- airkey-<yourname>.testnet
//
// 1. Registers the leash on wrap.testnet and on the tokens it can swap into,
//    so the wNEAR and the tokens Rhea sends back have somewhere to land. The
//    owner pays the small storage deposit for each (about 0.00125 NEAR).
// 2. Takes the old Trading Agent (trade.<owner>, which could only pay) off the
//    leash. Run `npm run add-trader` first: its trader.<owner> may also swap.
// 3. Prints the Trading Agent's caps and what the leash holds.
import { NETWORK, names, account, view, exists, fmt, txUrl } from "./common.mjs";

const RHEA_TOKENS = ["wrap.testnet", "usdt.itachicara.testnet", "usdc.itachicara.testnet"];

const [owner] = process.argv.slice(2);
if (!owner || NETWORK !== "testnet" || !owner.endsWith(".testnet")) {
  console.error("Usage: npm run setup-swaps -- airkey-<yourname>.testnet   (testnet only)");
  process.exit(1);
}
const n = names(owner);
const o = account(owner);

for (const token of RHEA_TOKENS) {
  const have = await view(token, "storage_balance_of", { account_id: n.leash });
  if (have) {
    console.log(`• ${n.leash} is already registered on ${token}`);
    continue;
  }
  const bounds = await view(token, "storage_balance_bounds");
  const res = await o.callFunctionRaw({
    contractId: token,
    methodName: "storage_deposit",
    args: { account_id: n.leash, registration_only: true },
    deposit: BigInt(bounds.min),
    gas: 30_000_000_000_000n,
  });
  console.log(`✓ registered ${n.leash} on ${token} (${fmt(bounds.min)})  ${txUrl(res.transaction.hash)}`);
}

const old = `trade.${owner}`;
if (old !== n.trade && (await view(n.leash, "get_agent", { agent: old }))) {
  const res = await o.callFunctionRaw({ contractId: n.leash, methodName: "remove_agent", args: { agent: old }, deposit: 1n, gas: 30_000_000_000_000n });
  console.log(`✓ took ${old} off the leash (it could only pay)  ${txUrl(res.transaction.hash)}`);
}

if (!(await exists(n.trade))) {
  console.log(`! ${n.trade} doesn't exist yet: run npm run add-trader -- ${owner}`);
} else {
  const agent = await view(n.leash, "get_agent", { agent: n.trade });
  console.log(agent ? `✓ ${n.trade}: ${fmt(agent.per_payment_cap)} a trade, ${fmt(agent.daily_cap)} a day` : `! ${n.trade} isn't on the leash`);
}
console.log(`  The leash can spend ${fmt(await view(n.leash, "available"))}.`);
