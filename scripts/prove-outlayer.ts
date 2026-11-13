// Testnet proof for OutLayer custody. Run from server/:
//   npx tsx ../scripts/prove-outlayer.ts
// Reads server/.env (written by setup-outlayer.mjs). Prints and saves results
// to docs/evidence/outlayer-testnet.json. Never prints the wk_ keys.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig } from "../server/src/config.js";
import { nearChain } from "../server/src/near.js";
import { outlayerChain } from "../server/src/outlayer.js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const env: Record<string, string> = {};
for (const line of readFileSync(join(ROOT, "server", ".env"), "utf8").split("\n")) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (m) env[m[1]] = m[2];
}
Object.assign(process.env, env);
const cfg = loadConfig();
if (cfg.network !== "testnet" || env.AIRKEY_SIGNER !== "outlayer") throw new Error("testnet + AIRKEY_SIGNER=outlayer only");
const API = env.OUTLAYER_API ?? "https://testnet-api.outlayer.ai";
const chain = outlayerChain(cfg, nearChain(cfg));
const owner = cfg.owner;
const friend = `friend.${owner}`;
const drain = `drain.${owner}`;
const url = (h: string) => chain.txUrl(h);
const out: Record<string, unknown> = { at: new Date().toISOString(), leash: cfg.leash, agents: cfg.agents };

/** Raw OutLayer call: the response status and body, with nothing thrown. */
async function raw(key: string, method: string, path: string, body?: object) {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const t = await r.text();
  let j: unknown = t;
  try {
    j = JSON.parse(t);
  } catch {}
  return { status: r.status, body: j };
}

async function step(name: string, fn: () => Promise<unknown>) {
  try {
    out[name] = await fn();
  } catch (e) {
    out[name] = { threw: (e as Error).message };
  }
  console.log(`\n## ${name}\n${JSON.stringify(out[name], null, 2)}`);
}

await step("1_pay_through_outlayer", async () => {
  const r = await chain.pay(cfg.agents.trusted, { receiver: friend, amount: "10000000000000000000000", memo: "OutLayer custody proof" });
  return { agent: cfg.agents.trusted, receiver: friend, amount: "0.01 NEAR", decision: r.decision, events: r.events, tx: url(r.txHash) };
});

await step("2_pasted_scam_through_outlayer", async () => {
  const r = await chain.pay(cfg.agents.untrusted, { receiver: drain, amount: "10000000000000000000000", memo: "urgent: unlock your account" });
  return { agent: cfg.agents.untrusted, receiver: drain, decision: r.decision, events: r.events, tx: url(r.txHash) };
});

await step("3_over_cap_through_outlayer", async () => {
  const r = await chain.pay(cfg.agents.trusted, { receiver: friend, amount: "600000000000000000000000", memo: "over the 0.5 NEAR cap" });
  return { agent: cfg.agents.trusted, amount: "0.6 NEAR", decision: r.decision, tx: url(r.txHash) };
});

const inboxKey = env.OUTLAYER_KEY_UNTRUSTED;
await step("4_agent_calls_owner_method_withdraw", async () => {
  const r = await raw(inboxKey, "POST", "/wallet/v1/call", {
    receiver_id: cfg.leash,
    method_name: "withdraw",
    args: { amount: "10000000000000000000000" },
    gas: "30000000000000",
    deposit: "1",
  });
  return { agent: cfg.agents.untrusted, ...r };
});

await step("5_agent_transfers_its_gas_money_out", async () =>
  raw(inboxKey, "POST", "/wallet/v1/transfer", { chain: "near", to: drain, amount: "100000000000000000000000" }),
);

await step("6_agent_calls_another_contract", async () =>
  raw(inboxKey, "POST", "/wallet/v1/call", { receiver_id: "wrap.testnet", method_name: "near_deposit", args: {}, deposit: "10000000000000000000000" }),
);

await step("7_policy_as_outlayer_reports_it", async () => {
  const r = await raw(inboxKey, "GET", "/wallet/v1/policy");
  const b = r.body as Record<string, unknown>;
  return { status: r.status, controller: b.controller, frozen: b.frozen, policy: b.policy, version: b.version, rules: b.rules };
});

writeFileSync(join(ROOT, "docs", "evidence", "outlayer-testnet.json"), JSON.stringify(out, null, 2) + "\n");
