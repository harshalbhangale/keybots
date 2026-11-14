// The mainnet setup plan for Spend Limits, as plain data: who signs what, to
// whom, with how much NEAR and gas. No network and no keys here, so the plan
// can be printed, checked and tested before anything is signed.
// scripts/setup-mainnet.mjs reads the chain, prints this plan, and signs one
// step at a time only when asked.

export const YOCTO = 10n ** 24n;
/** NEAR's storage price: 1 NEAR per 100 KB (10^19 yoctoNEAR a byte). */
export const STORAGE_PER_BYTE = 10n ** 19n;
export const TGAS = 10n ** 12n;
/** Mainnet's minimum gas price (yoctoNEAR a unit of gas): 1 TGas costs 0.0001 NEAR. */
export const MIN_GAS_PRICE = 100_000_000n;

export const RHEA_MAINNET = "v2.ref-finance.near";
export const WRAP_MAINNET = "wrap.near";
export const USDC_MAINNET = "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1";
export const USDT_MAINNET = "usdt.tether-token.near";

/** "0.25" NEAR -> yoctoNEAR, exact. */
export function toYocto(near) {
  const [i, f = ""] = String(near).split(".");
  if (!/^\d+$/.test(i) || !/^\d*$/.test(f) || f.length > 24) throw new Error(`Not a NEAR amount: ${near}`);
  return BigInt(i) * YOCTO + BigInt((f + "0".repeat(24)).slice(0, 24));
}

/** yoctoNEAR -> "2.5520" NEAR (4 places, rounded up so a cost is never shown low). */
export function fmtNear(yocto, places = 4) {
  const unit = 10n ** BigInt(24 - places);
  const up = (BigInt(yocto) + unit - 1n) / unit;
  const s = up.toString().padStart(places + 1, "0");
  return `${s.slice(0, -places)}.${s.slice(-places)}`;
}

/** The account names, all under the owner. */
export function mainnetNames(owner = "hellbuddy.near") {
  return {
    owner,
    limits: `limits.${owner}`,
    pay: `pay.${owner}`, // trusted: acts on what the owner types
    inbox: `inbox.${owner}`, // untrusted: acts on pasted or inbound text
    trader: `trader.${owner}`, // trusted, may also swap
  };
}

/** Small caps for the first mainnet run, in NEAR. */
export const MAINNET_AGENTS = [
  { key: "pay", name: "Pay Agent", tier: "trusted", perPayment: "0.2", perDay: "0.5", methods: ["pay", "report"] },
  { key: "inbox", name: "Inbox Agent", tier: "untrusted", perPayment: "0.1", perDay: "0.2", methods: ["pay", "report"] },
  { key: "trader", name: "Trading Agent", tier: "trusted", perPayment: "0.3", perDay: "0.6", methods: ["pay", "report", "swap"] },
];

/**
 * The steps, in order. `opts`:
 *   owner        "hellbuddy.near"
 *   wasmBytes    size of airkey_leash.wasm
 *   fund         NEAR to add to Spend Limits with fund() (default "0.5")
 *   agentBalance NEAR each agent account starts with, for its own gas (default "0.1")
 *   keyAllowance NEAR of gas each agent key may burn (default "0.25"; it can't exceed the account's balance anyway)
 *   storage      { [token]: yocto string } NEP-145 registration cost per token (read from chain; default 0.00125)
 *   tokenRule    { maxPerTrade: "1", minValueNear: "0.25" } per stablecoin, or null to skip
 *   done         { [stepId]: true } steps the chain shows as done already
 */
export function mainnetPlan(opts) {
  const owner = opts.owner ?? "hellbuddy.near";
  const n = mainnetNames(owner);
  const wasmBytes = BigInt(opts.wasmBytes);
  const fund = toYocto(opts.fund ?? "0.5");
  const agentBalance = toYocto(opts.agentBalance ?? "0.1");
  const allowance = toYocto(opts.keyAllowance ?? "0.25");
  const reg = (t) => BigInt(opts.storage?.[t] ?? "1250000000000000000000");
  const done = opts.done ?? {};

  // The contract's code is stored on its account: 1 NEAR per 100 KB, plus
  // room for the account, its state (agents, lists) and a margin of 0.1 NEAR.
  const codeStorage = wasmBytes * STORAGE_PER_BYTE;
  const limitsBalance = codeStorage + toYocto("0.1");

  const steps = [];
  const add = (s) => steps.push({ n: steps.length + 1, ...s, done: !!done[s.id] });

  add({
    id: "limits",
    title: `Create ${n.limits}, put the Spend Limits code on it, and start it with ${owner} as owner`,
    signer: owner,
    receiver: n.limits,
    actions: [
      { action: "CreateAccount" },
      { action: "Transfer", deposit: limitsBalance, note: `${fmtNear(codeStorage)} NEAR for the code's storage (${opts.wasmBytes} bytes) + 0.1 NEAR for state` },
      { action: "AddKey", note: `full-access key for ${n.limits}, fresh, saved to keys/${n.limits}.json (needed to update the code later; delete it to lock the code)` },
      { action: "DeployContract", note: `contracts/leash/target/near/airkey_leash.wasm, ${opts.wasmBytes} bytes` },
      { action: "FunctionCall", method: "new", args: { owner }, deposit: 0n, gas: 30n * TGAS },
    ],
  });

  for (const a of MAINNET_AGENTS) {
    const id = n[a.key];
    add({
      id: a.key,
      title: `Create ${id} (${a.name}) whose only key may call ${a.methods.join(", ")} on ${n.limits}`,
      signer: owner,
      receiver: id,
      actions: [
        { action: "CreateAccount" },
        { action: "Transfer", deposit: agentBalance, note: "its own gas money" },
        { action: "AddKey", note: `function-call key for ${n.limits} (${a.methods.join(", ")}), gas allowance ${fmtNear(allowance)} NEAR, fresh, saved to keys/${id}.json, never printed`, methods: a.methods, allowance },
      ],
    });
  }

  add({
    id: "agents",
    title: "Register the three agents on Spend Limits with their limits",
    signer: owner,
    receiver: n.limits,
    actions: MAINNET_AGENTS.map((a) => ({
      action: "FunctionCall",
      method: "add_agent",
      args: { agent: n[a.key], tier: a.tier, per_payment_cap: toYocto(a.perPayment).toString(), daily_cap: toYocto(a.perDay).toString() },
      deposit: 1n,
      gas: 10n * TGAS,
      note: `${a.name}: ${a.perPayment} NEAR a payment, ${a.perDay} NEAR a day`,
    })),
  });

  add({
    id: "fund",
    title: `Put ${fmtNear(fund)} NEAR into Spend Limits for the agents to spend`,
    signer: owner,
    receiver: n.limits,
    actions: [{ action: "FunctionCall", method: "fund", args: {}, deposit: fund, gas: 10n * TGAS }],
  });

  // Somewhere for what Rhea sends back to land: Spend Limits registers on wNEAR and both stablecoins.
  for (const [symbol, token] of [["wNEAR", WRAP_MAINNET], ["USDC", USDC_MAINNET], ["USDT", USDT_MAINNET]]) {
    add({
      id: `storage-${symbol}`,
      title: `Register ${n.limits} on ${symbol} (${token}) so swaps can land there`,
      signer: owner,
      receiver: token,
      actions: [{ action: "FunctionCall", method: "storage_deposit", args: { account_id: n.limits, registration_only: true }, deposit: reg(token), gas: 30n * TGAS }],
    });
  }

  if (opts.tokenRule !== null) {
    const rule = opts.tokenRule ?? { maxPerTrade: "1", minValueNear: "0.25" };
    const units = toYocto(rule.maxPerTrade) / 10n ** 18n; // 6 decimals
    add({
      id: "token-rules",
      title: `Let the Trading Agent sell USDC and USDT back, at most ${rule.maxPerTrade} a trade, only on Rhea`,
      signer: owner,
      receiver: n.limits,
      optional: true,
      actions: [USDC_MAINNET, USDT_MAINNET].map((token) => ({
        action: "FunctionCall",
        method: "set_token_cap",
        args: { token, max_per_trade: units.toString(), venue: RHEA_MAINNET, min_value: toYocto(rule.minValueNear).toString() },
        deposit: 1n,
        gas: 10n * TGAS,
        note: `${token === USDC_MAINNET ? "USDC" : "USDT"}: a full trade counts for at least ${rule.minValueNear} NEAR against the limits`,
      })),
    });
  }

  // Money each step moves (deposits) and the most its gas can cost.
  let running = 0n;
  for (const s of steps) {
    s.deposit = s.actions.reduce((t, a) => t + (a.deposit ?? 0n), 0n);
    s.gas = s.actions.reduce((t, a) => t + (a.gas ?? 0n), 0n) + 5n * TGAS; // + the actions' own fees
    s.maxGasFee = s.gas * (opts.gasPrice ? BigInt(opts.gasPrice) : MIN_GAS_PRICE);
    if (!s.done) running += s.deposit + s.maxGasFee;
    s.runningTotal = running;
  }
  return { names: n, steps, codeStorage, total: running };
}

/** One step as the lines the owner reads before approving it. */
export function describeStep(s) {
  const out = [`Step ${s.n}${s.optional ? " (optional)" : ""}: ${s.title}${s.done ? "  [already done]" : ""}`];
  out.push(`  signer:   ${s.signer}`);
  out.push(`  receiver: ${s.receiver}`);
  for (const a of s.actions) {
    const bits = [a.action];
    if (a.method) bits.push(`${a.method}(${JSON.stringify(a.args)})`);
    if (a.deposit !== undefined) bits.push(`deposit ${a.deposit === 1n ? "1 yoctoNEAR" : `${fmtNear(a.deposit)} NEAR`}`);
    if (a.gas) bits.push(`gas ${a.gas / TGAS} TGas`);
    out.push(`    - ${bits.join("  ")}${a.note ? `  (${a.note})` : ""}`);
  }
  out.push(`  this step: ${fmtNear(s.deposit)} NEAR + at most ${fmtNear(s.maxGasFee)} NEAR gas   running total: ${fmtNear(s.runningTotal)} NEAR`);
  return out.join("\n");
}
