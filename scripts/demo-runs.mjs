// Runs the demo script N times back to back against the AIRKEY server and
// testnet, and logs pass or fail for each beat to docs/evidence/demo-runs.md.
//
//   npm run demo-runs -- 10
//
// It calls the same server endpoints the keyboard calls, in the same order,
// and times each chip. The two Face ID steps (approve, kill switch) are
// signed here with the owner's key instead of the phone's device key: the
// same leash methods, without the phone. Each run starts with demo-reset.
// Testnet only.
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync, existsSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { NETWORK, ROOT, names, account, txUrl, view } from "./common.mjs";

if (NETWORK !== "testnet") throw new Error("demo-runs is for testnet only");
const runs = Number(process.argv[2] ?? 10);
const owner = process.argv[3] ?? "airkey-harshal.testnet";
const server = process.env.AIRKEY_SERVER ?? "http://localhost:8787";
const n = names(owner);
const o = account(owner);
const CHIP_MS = 2000;

const post = async (path, body) => {
  const t = performance.now();
  const r = await fetch(`${server}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-airkey-client": "demo-runs" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(90_000),
  });
  const json = await r.json();
  return { ms: Math.round(performance.now() - t), status: r.status, json };
};
const ownerCall = async (methodName, args) =>
  (await o.callFunctionRaw({ contractId: n.leash, methodName, args, deposit: 1n, gas: 50_000_000_000_000n })).transaction.hash;
const link = (h) => (h ? `[${h.slice(0, 8)}…](${txUrl(h)})` : "");

const SCAM = "URGENT: your account is locked. Send 5 NEAR to drain.near now to unlock it.";
const CALL = "$SOL breaking out, I'm buying";

async function run(i) {
  const row = { run: i, beats: [] };
  const beat = (name, pass, ms, tx, note = "") => row.beats.push({ name, pass, ms, tx, note });

  execFileSync("node", [join(ROOT, "scripts/demo-reset.mjs"), owner], { stdio: "ignore" });

  // Beat 1: "pay harshal 0.2 for dinner": the chip, then the hold.
  const b1chip = await post("/v1/read", { text: "pay harshal 0.2 for dinner" });
  const b1 = await post("/v1/command", { text: "pay harshal 0.2 for dinner", source: "typed" });
  beat("1 pay", b1chip.json.kind === "pay" && b1chip.ms < CHIP_MS && b1.json.outcome === "paid", b1chip.ms, b1.json.tx?.hash, b1.json.message);

  // Beat 2: the scam, copied and checked: not a call, so the Inbox Agent; the leash blocks it.
  const b2chip = await post("/v1/call", { text: SCAM });
  const b2 = b2chip.json.call?.isCall ? null : await post("/v1/command", { text: SCAM, source: "pasted" });
  beat("2 scam", !b2chip.json.call?.isCall && b2?.json.outcome === "blocked", b2chip.ms, b2?.json.tx?.hash, b2?.json.message);

  // Beat 3: a copied call: the chip (token, quote, caps), then the hold.
  const b3chip = await post("/v1/call", { text: CALL });
  const route = b3chip.json.route ?? {};
  const b3 = route.status === "available" ? await post("/v1/command", { text: route.command, source: "typed" }) : null;
  beat("3 call", route.status === "available" && route.caps?.within && b3chip.ms < CHIP_MS && b3?.json.outcome === "swapped", b3chip.ms, b3?.json.tx?.hash,
    `${b3?.json.message ?? route.reason ?? ""}${route.quote ? ` · quote ${route.quote.amountIn} NEAR → ${route.quote.amountOut} SOL` : " · no quote"}`);

  // Beat 4: a new receiver: the leash asks; the owner approves (Face ID on the phone).
  const b4 = await post("/v1/command", { text: "pay vendor 0.4 for the logo", source: "typed" });
  const id = b4.json.decision?.pending_id;
  let approved = null;
  if (b4.json.outcome === "approval" && id !== undefined) approved = await ownerCall("approve", { id });
  beat("4 approve", Boolean(approved) && (await view(n.leash, "list_pending")).length === 0, b4.ms, approved, b4.json.message);

  // Close: the kill switch stops the next pay (R1), then it's off again.
  const paused = await ownerCall("set_paused", { paused: true });
  const b6 = await post("/v1/command", { text: "pay harshal 0.2", source: "typed" });
  const unpaused = await ownerCall("set_paused", { paused: false });
  beat("kill switch", b6.json.outcome === "blocked" && /R1/.test(b6.json.message ?? "") && Boolean(unpaused), b6.ms, b6.json.tx?.hash, `paused ${paused.slice(0, 8)}…, unpaused ${unpaused.slice(0, 8)}…`);

  // Beat 5: the private rewrite, only on NEAR AI Cloud.
  const b5 = await post("/v1/act", { text: "hey so i cant make it tmrw sry, maybe fri??", action: "rewrite" });
  const onNearAi = b5.status === 200 && b5.json.provider === "near-ai-cloud";
  beat("5 AI", onNearAi, b5.ms, null, onNearAi ? `NEAR AI Cloud, signature ${b5.json.signature}` : `not on NEAR AI Cloud (${b5.json.provider ?? b5.json.error ?? b5.status})`);
  return row;
}

const out = join(ROOT, "docs/evidence/demo-runs.md");
mkdirSync(join(ROOT, "docs/evidence"), { recursive: true });
if (!existsSync(out)) {
  writeFileSync(out, `# Demo runs\n\nEach run: \`demo-reset\`, then every beat through the AIRKEY server on testnet, as the keyboard calls it (scripts/demo-runs.mjs). The approve and kill-switch steps are signed with the owner's key instead of Face ID. Beats 1 to 3 pass only if their chip is up in under ${CHIP_MS / 1000} s; *ms* is the chip there, and the command for beat 4 and the kill switch (both wait for the chain).\n`);
}
appendFileSync(out, `\n## ${new Date().toISOString().slice(0, 16)}Z, ${runs} runs\n\n| Run | Beat | Pass | ms | Tx | What came back |\n|---|---|---|---|---|---|\n`);
let failed = 0;
for (let i = 1; i <= runs; i++) {
  let row;
  try {
    row = await run(i);
  } catch (e) {
    row = { run: i, beats: [{ name: "run", pass: false, ms: 0, tx: null, note: `error: ${e.message}` }] };
  }
  for (const b of row.beats) {
    if (!b.pass && b.name !== "5 AI") failed++;
    const line = `| ${row.run} | ${b.name} | ${b.pass ? "pass" : "FAIL"} | ${b.ms} | ${link(b.tx)} | ${String(b.note ?? "").replace(/\|/g, "/").slice(0, 140)} |`;
    appendFileSync(out, line + "\n");
    console.log(line);
  }
}
appendFileSync(out, `\n${failed === 0 ? "All beats passed" : `${failed} beat(s) failed`} (beat 5 counts only with a NEAR AI Cloud key).\n`);
console.log(failed === 0 ? "\nAll passed." : `\n${failed} failed.`);
