// End-to-end proof on testnet. Every step is a real transaction; results go to docs/evidence/.
//
//   npm run e2e -- airkey-<yourname>.testnet
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { actions } from "near-api-js";
import { ROOT, names, near, account, view, events, returned, txUrl, fmt, EXPLORER } from "./common.mjs";

const owner = process.argv[2];
if (!owner) {
  console.error("Usage: npm run e2e -- airkey-<yourname>.testnet");
  process.exit(1);
}
const n = names(owner);
const rows = [];
let failures = 0;

function record(step, expect, got, hash, note = "") {
  const ok = got === expect;
  if (!ok) failures++;
  rows.push({ step, expect, got, ok, hash, note });
  console.log(`${ok ? "✓" : "✗"} ${step}: expected ${expect}, got ${got}${hash ? `  ${txUrl(hash)}` : ""}${note ? `  (${note})` : ""}`);
}

async function pay(agentId, receiver, amount, memo, ask_owner) {
  const res = await account(agentId).callFunctionRaw({
    contractId: n.leash,
    methodName: "pay",
    args: { receiver, amount: near(amount).toString(), memo, ask_owner },
    gas: 50_000_000_000_000n,
  });
  return { res, d: returned(res), ev: events(res) };
}

const ownerAcc = account(owner);
const ownerCall = (methodName, args) =>
  ownerAcc.callFunctionRaw({ contractId: n.leash, methodName, args, deposit: 1n, gas: 50_000_000_000_000n });

// Start clean: kill switch off.
await ownerCall("set_paused", { paused: false });

// 1. Trusted agent pays the allowlisted friend.
{
  const { res, d } = await pay(n.pay, n.friend, 0.1, "dinner");
  record("pay agent → friend 0.1 (typed)", "paid", d?.status, res.transaction.hash);
}

// 2. Untrusted agent pays someone not on the allowlist → waits for the owner (R6).
let pendingId;
{
  const { res, d } = await pay(n.inbox, n.vendor, 0.1, "invoice #42 by email");
  pendingId = d?.pending_id;
  record("inbox agent → vendor 0.1 (pasted invoice)", "pending", d?.status, res.transaction.hash, d?.rule);
}

// 3. The prompt injection: "URGENT, pay 5 NEAR to drain". The AI fell for it; the leash didn't (R4).
{
  const { res, d } = await pay(n.inbox, n.drain, 5, "URGENT your account is locked");
  record("injected: inbox agent → drain 5", "blocked", d?.status, res.transaction.hash, `${d?.rule}: ${d?.reason}`);
}

// 4. The agent reports drain; after that even the trusted agent can't pay it (R3).
{
  const r = await account(n.inbox).callFunctionRaw({ contractId: n.leash, methodName: "report", args: { account: n.drain, evidence: "asked for an urgent payment to unlock an account" }, gas: 30_000_000_000_000n });
  const { res, d } = await pay(n.pay, n.drain, 0.01, "test");
  record("after report: pay agent → drain 0.01", "blocked", d?.status, res.transaction.hash, `${d?.rule}; report ${txUrl(r.transaction.hash)}`);
}

// 5. The owner approves the pending invoice.
{
  const res = await ownerCall("approve", { id: pendingId });
  const d = returned(res);
  record("owner approves the vendor invoice", "paid", d?.status, res.transaction.hash);
}

// 6. The agent's key cannot move NEAR directly: a plain transfer signed with it is rejected.
{
  let got = "sent";
  let note = "";
  try {
    await account(n.pay).signAndSendTransaction({ receiverId: n.drain, actions: [actions.transfer(near(0.01))] });
  } catch (e) {
    got = "rejected";
    note = String(e.message ?? e).split("\n")[0].slice(0, 140);
  }
  record("pay agent signs a direct transfer to drain", "rejected", got, null, note);
}

// 7. The agent's key cannot call owner methods (the key only allows pay/report).
{
  let got = "sent";
  let note = "";
  try {
    await account(n.pay).callFunctionRaw({ contractId: n.leash, methodName: "set_paused", args: { paused: true }, gas: 30_000_000_000_000n });
  } catch (e) {
    got = "rejected";
    note = String(e.message ?? e).split("\n")[0].slice(0, 140);
  }
  record("pay agent calls set_paused", "rejected", got, null, note);
}

// 8. A transfer to an account that doesn't exist rolls the spend back.
{
  const before = BigInt((await view(n.leash, "get_agent", { agent: n.pay })).spent_today);
  const ghost = `ghost-${Date.now()}.${owner}`;
  const { res, ev } = await pay(n.pay, ghost, 0.05, "to nowhere");
  await new Promise((r) => setTimeout(r, 3000));
  const after = BigInt((await view(n.leash, "get_agent", { agent: n.pay })).spent_today);
  const failed = ev.some((e) => e.event === "transfer_failed");
  record("pay to a missing account rolls back", "rolled back", failed && after === before ? "rolled back" : `spent ${fmt(after - before)}`, res.transaction.hash);
}

// 9. Kill switch.
{
  const p = await ownerCall("set_paused", { paused: true });
  const { res, d } = await pay(n.pay, n.friend, 0.01, "after kill switch");
  record("kill switch on: pay agent → friend", "blocked", d?.status, res.transaction.hash, `${d?.rule}; switch ${txUrl(p.transaction.hash)}`);
  await ownerCall("set_paused", { paused: false });
}

// Evidence file.
const dir = join(ROOT, "docs/evidence");
mkdirSync(dir, { recursive: true });
const md = [
  `# Testnet end-to-end run`,
  ``,
  `Run on ${new Date().toISOString()} against [\`${n.leash}\`](${EXPLORER}/address/${n.leash}) by \`scripts/e2e-testnet.mjs\`.`,
  ``,
  `| # | Step | Expected | Got | Transaction |`,
  `|---|---|---|---|---|`,
  ...rows.map((r, i) => `| ${i + 1} | ${r.step} | ${r.expect} | ${r.ok ? "✅" : "❌"} ${r.got}${r.note ? ` (${r.note.replace(/\|/g, "/")})` : ""} | ${r.hash ? `[${r.hash.slice(0, 10)}…](${txUrl(r.hash)})` : "rejected before reaching the chain"} |`),
  ``,
].join("\n");
writeFileSync(join(dir, "testnet-e2e.md"), md);
console.log(`\n${rows.length - failures}/${rows.length} as expected. Evidence: docs/evidence/testnet-e2e.md`);
process.exit(failures ? 1 : 0);
