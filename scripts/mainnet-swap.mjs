// One real mainnet swap from the owner's account: NEAR -> USDC on Rhea (pool 4512).
// Dry run by default: prints every transaction and the live quote, signs nothing.
//   node mainnet-swap.mjs              (dry run)
//   node mainnet-swap.mjs --yes        (signs and sends, owner approved)
import { actions } from "near-api-js";
// Mainnet only: set before common.mjs reads it.
process.env.NEAR_NETWORK = "mainnet";
const { account, view: rawView, provider, near: toYocto } = await import("./common.mjs");

const OWNER = "hellbuddy.near";
const WRAP = "wrap.near";
const USDC = "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1";
const RHEA = "v2.ref-finance.near";
const POOL = 4512;
const AMOUNT = process.env.SWAP_NEAR ?? "0.15";
const SLIPPAGE = 0.01;
const go = process.argv.includes("--yes");
const acct = account(OWNER);
const fmtN = (y, d = 4) => (Number(BigInt(y)) / 1e24).toFixed(d);

const view = (c, m, a) => rawView(c, m, a);
const yocto = toYocto(AMOUNT).toString();
const out = await view(RHEA, "get_return", { pool_id: POOL, token_in: WRAP, amount_in: yocto, token_out: USDC });
const min = ((BigInt(out) * BigInt(Math.round((1 - SLIPPAGE) * 10000))) / 10000n).toString();
const wrapReg = await view(WRAP, "storage_balance_of", { account_id: OWNER });
const usdcReg = await view(USDC, "storage_balance_of", { account_id: OWNER });
const bal = await provider.viewAccount({ accountId: OWNER, blockQuery: { finality: "final" } });

const usdc = (u) => (Number(u) / 1e6).toFixed(4);
console.log(`Owner ${OWNER}: ${fmtN(bal.amount)} NEAR`);
console.log(`Quote: ${AMOUNT} NEAR -> ${usdc(out)} USDC on Rhea pool ${POOL}; at least ${usdc(min)} (1% slippage)\n`);
const STORAGE = toYocto("0.00125").toString();
const msg = JSON.stringify({ actions: [{ pool_id: POOL, token_in: WRAP, token_out: USDC, amount_in: yocto, min_amount_out: min }] });
const txs = [
  { to: WRAP, label: `${wrapReg ? "" : "register + "}wrap ${AMOUNT} NEAR`, actions: [
    ...(wrapReg ? [] : [["storage_deposit", { account_id: OWNER, registration_only: true }, STORAGE]]),
    ["near_deposit", {}, yocto],
  ] },
  ...(usdcReg ? [] : [{ to: USDC, label: "register to hold USDC", actions: [["storage_deposit", { account_id: OWNER, registration_only: true }, STORAGE]] }]),
  { to: WRAP, label: `swap ${AMOUNT} wNEAR -> USDC on Rhea pool ${POOL}`, actions: [["ft_transfer_call", { receiver_id: RHEA, amount: yocto, msg }, "1"]] },
];
txs.forEach((t, i) => {
  console.log(`${i + 1}. ${OWNER} -> ${t.to}: ${t.label}`);
  for (const [m, a, d] of t.actions) console.log(`     ${m}  deposit ${d === "1" ? "1 yocto" : fmtN(d, 5) + " NEAR"}`);
});
if (!go) {
  console.log("\nDry run: nothing was signed. Run with --yes to send.");
  process.exit(0);
}
for (const [i, t] of txs.entries()) {
  const r = await acct.signAndSendTransaction({
    receiverId: t.to,
    actions: t.actions.map(([m, a, d]) => actions.functionCall(m, a, BigInt(m === "ft_transfer_call" ? "180000000000000" : "30000000000000"), BigInt(d))),
  });
  const failed = JSON.stringify(r.status).includes("Failure") || r.receipts_outcome.some((o) => o.outcome.status.Failure);
  const logs = r.receipts_outcome.flatMap((o) => o.outcome.logs).filter((l) => /Swapped|refund|Failure/i.test(l));
  console.log(`${i + 1}. ${failed ? "FAILED" : "ok"}  https://nearblocks.io/txns/${r.transaction.hash}${logs.length ? "\n   " + logs.join("\n   ") : ""}`);
  if (failed) process.exit(1);
}
const after = await view(USDC, "ft_balance_of", { account_id: OWNER });
console.log(`\nUSDC in ${OWNER}: ${usdc(after)}`);
