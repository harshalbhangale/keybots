// Adds the Trading Agent to an existing deployment (testnet).
//
//   npm run add-trader -- airkey-<yourname>.testnet [perTradeNear] [perDayNear]
//
// Creates trader.<owner>, whose only key is a function-call key for the
// leash's pay, report and swap, and registers it on the leash as a trusted
// agent with its own caps. Swaps are held to these caps, so trading never eats
// into what the Payment Agent may spend.
import { actions } from "near-api-js";
import { NETWORK, names, near, newKey, saveKey, account, exists, txUrl, view, fmt } from "./common.mjs";

const [owner, perTrade = "1", perDay = "2"] = process.argv.slice(2);
if (!owner || NETWORK !== "testnet" || !owner.endsWith(".testnet")) {
  console.error("Usage: npm run add-trader -- airkey-<yourname>.testnet [perTradeNear] [perDayNear]   (testnet only)");
  process.exit(1);
}
const n = names(owner);
const o = account(owner);

if (await exists(n.trade)) {
  console.log(`• ${n.trade} already exists`);
} else {
  const kp = newKey();
  saveKey(n.trade, kp);
  const res = await o.signAndSendTransaction({
    receiverId: n.trade,
    actions: [
      actions.createAccount(),
      actions.transfer(near(0.3)),
      actions.addFunctionCallAccessKey(kp.getPublicKey(), n.leash, ["pay", "report", "swap"], near(0.25)),
    ],
  });
  console.log(`✓ created ${n.trade}  ${txUrl(res.transaction.hash)}`);
}

const res = await o.callFunction({
  contractId: n.leash,
  methodName: "add_agent",
  args: { agent: n.trade, tier: "trusted", per_payment_cap: near(perTrade).toString(), daily_cap: near(perDay).toString() },
  deposit: 1n,
});
const agent = await view(n.leash, "get_agent", { agent: n.trade });
console.log(`✓ registered on the leash: ${fmt(agent.per_payment_cap)} a trade, ${fmt(agent.daily_cap)} a day`);
if (res?.transaction?.hash) console.log(`  ${txUrl(res.transaction.hash)}`);
