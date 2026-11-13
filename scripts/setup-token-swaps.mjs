// Lets the Trading Agent sell the tokens the leash holds on Rhea (testnet only):
// USDC → NEAR, USDT → NEAR, USDC ↔ USDT. Safe to run again; it only sends what's missing.
//
//   npm run setup-token-swaps -- airkey-<yourname>.testnet [maxPerTrade] [minNearPerMax]
//
// Another leash (say leash2.<owner>, to try new contract code): set AIRKEY_LEASH.
//
// 1. Registers the leash on wrap.testnet and on each token, so what Rhea sends
//    back has somewhere to land (the owner pays about 0.00125 NEAR each).
// 2. As the owner, sets the leash's rule for each token (set_token_cap): at
//    most `maxPerTrade` tokens a trade (default 5), only at Rhea, and a full
//    trade counts for at least `minNearPerMax` NEAR (default 1) against the
//    agent's caps, whatever value the agent states.
import { NETWORK, names, account, view, fmt, near, txUrl } from "./common.mjs";

const VENUE = "ref-finance-101.testnet";
const WRAP = "wrap.testnet";
const TOKENS = [
  { symbol: "USDC", token: "usdc.itachicara.testnet", decimals: 24 },
  { symbol: "USDT", token: "usdt.itachicara.testnet", decimals: 24 },
];

const [owner, maxPerTrade = "5", minNearPerMax = "1"] = process.argv.slice(2);
if (!owner || NETWORK !== "testnet" || !owner.endsWith(".testnet") || !/^\d+$/.test(maxPerTrade)) {
  console.error("Usage: npm run setup-token-swaps -- airkey-<yourname>.testnet [maxPerTrade] [minNearPerMax]   (testnet only)");
  process.exit(1);
}
const n = names(owner);
const o = account(owner);
console.log(`Leash: ${n.leash}`);

for (const token of [WRAP, ...TOKENS.map((t) => t.token)]) {
  if (await view(token, "storage_balance_of", { account_id: n.leash })) {
    console.log(`• registered on ${token}`);
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
  console.log(`✓ registered on ${token} (${fmt(bounds.min)})  ${txUrl(res.transaction.hash)}`);
}

for (const t of TOKENS) {
  const want = { max_per_trade: (BigInt(maxPerTrade) * 10n ** BigInt(t.decimals)).toString(), venue: VENUE, min_value: near(minNearPerMax).toString() };
  let have;
  try {
    have = await view(n.leash, "get_token_cap", { token: t.token });
  } catch {
    console.error(`! ${n.leash} runs contract code without token rules. Deploy the new code first (npm run deploy).`);
    process.exit(1);
  }
  const what = `${t.symbol}: at most ${maxPerTrade} a trade at ${VENUE}, counted as at least ${minNearPerMax} NEAR per ${maxPerTrade}`;
  if (have && have.max_per_trade === want.max_per_trade && have.venue === want.venue && have.min_value === want.min_value) {
    console.log(`• ${what}`);
    continue;
  }
  const res = await o.callFunctionRaw({ contractId: n.leash, methodName: "set_token_cap", args: { token: t.token, ...want }, deposit: 1n, gas: 30_000_000_000_000n });
  console.log(`✓ ${what}  ${txUrl(res.transaction.hash)}`);
}

const agent = await view(n.leash, "get_agent", { agent: n.trade });
console.log(agent ? `  ${n.trade}: ${fmt(agent.per_payment_cap)} a trade, ${fmt(agent.daily_cap)} a day` : `! ${n.trade} isn't on this leash`);
for (const t of TOKENS) {
  const held = await view(t.token, "ft_balance_of", { account_id: n.leash });
  console.log(`  holds ${Number(BigInt(held) / 10n ** BigInt(t.decimals - 4)) / 1e4} ${t.symbol}`);
}
