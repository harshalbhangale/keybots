// Mainnet setup for hellbuddy.near, checked with fakes: no network here.
import { describe, expect, it } from "vitest";
import { loadConfig, mainnetCap } from "../src/config.js";
import { intentsLanding } from "../src/intents.js";
import { RHEA } from "../src/rhea.js";
// @ts-expect-error plain JS module, no types
import { describeStep, fmtNear, mainnetPlan, toYocto } from "../../scripts/mainnet-plan.mjs";

describe("mainnet config", () => {
  it("defaults to hellbuddy.near with Spend Limits on limits.hellbuddy.near and nearblocks.io", () => {
    const c = loadConfig({ NEAR_NETWORK: "mainnet" });
    expect(c.network).toBe("mainnet");
    expect(c.owner).toBe("hellbuddy.near");
    expect(c.leash).toBe("limits.hellbuddy.near");
    expect(c.agents).toEqual({ trusted: "pay.hellbuddy.near", untrusted: "inbox.hellbuddy.near", trade: "trader.hellbuddy.near" });
    expect(c.explorer).toBe("https://nearblocks.io");
    // No made-up contacts on mainnet.
    expect(c.contacts).toEqual({});
    expect(c.mainnetUsdCap).toBe(1);
  });

  it("keeps testnet as it was", () => {
    const c = loadConfig({});
    expect(c.leash).toBe("leash.airkey-harshal.testnet");
    expect(c.explorer).toBe("https://testnet.nearblocks.io");
  });

  it("holds the dollar ceiling to a real number", () => {
    expect(mainnetCap(undefined)).toBe(1);
    expect(mainnetCap("0.5")).toBe(0.5);
    expect(mainnetCap("lots")).toBe(1);
    expect(mainnetCap("-3")).toBe(1);
  });

  it("swaps NEAR to USDC and USDT on Rhea's mainnet pools", () => {
    expect(RHEA.mainnet?.routes.USDC.pool).toBe(4512);
    expect(RHEA.mainnet?.routes.USDT.pool).toBe(6063);
    expect(RHEA.mainnet?.pairs?.["USDC/USDT"]).toBe(6416);
  });

  it("says where a NEAR Intents buy lands", () => {
    expect(intentsLanding("hellbuddy.near", "near")).toBe("It lands in hellbuddy.near, your NEAR account.");
    expect(intentsLanding("hellbuddy.near", "sol")).toMatch(/hellbuddy\.near's NEAR Intents balance \(sol tokens stay there until you withdraw them at app\.near-intents\.org\)/);
  });
});

describe("the mainnet setup plan", () => {
  const plan = mainnetPlan({ owner: "hellbuddy.near", wasmBytes: 255197, fund: "0.5" });

  it("has the steps in order, each signed by the owner", () => {
    expect(plan.steps.map((s: { id: string }) => s.id)).toEqual(["limits", "pay", "inbox", "trader", "agents", "fund", "storage-wNEAR", "storage-USDC", "storage-USDT", "token-rules"]);
    expect(plan.steps.every((s: { signer: string }) => s.signer === "hellbuddy.near")).toBe(true);
  });

  it("pays for the code's storage at 1 NEAR per 100 KB", () => {
    expect(plan.codeStorage).toBe(255197n * 10n ** 19n);
    const create = plan.steps[0];
    expect(create.receiver).toBe("limits.hellbuddy.near");
    expect(create.deposit).toBe(255197n * 10n ** 19n + toYocto("0.1"));
    expect(create.actions.map((a: { action: string }) => a.action)).toEqual(["CreateAccount", "Transfer", "AddKey", "DeployContract", "FunctionCall"]);
  });

  it("gives each agent only a function-call key, the trader alone may swap", () => {
    const keys = plan.steps.filter((s: { id: string }) => ["pay", "inbox", "trader"].includes(s.id)).map((s: { actions: { methods?: string[] }[] }) => s.actions[2].methods);
    expect(keys).toEqual([["pay", "report"], ["pay", "report"], ["pay", "report", "swap"]]);
  });

  it("registers the agents with the small caps", () => {
    const args = plan.steps[4].actions.map((a: { args: object }) => a.args);
    expect(args).toEqual([
      { agent: "pay.hellbuddy.near", tier: "trusted", per_payment_cap: toYocto("0.2").toString(), daily_cap: toYocto("0.5").toString() },
      { agent: "inbox.hellbuddy.near", tier: "untrusted", per_payment_cap: toYocto("0.1").toString(), daily_cap: toYocto("0.2").toString() },
      { agent: "trader.hellbuddy.near", tier: "trusted", per_payment_cap: toYocto("0.3").toString(), daily_cap: toYocto("0.6").toString() },
    ]);
  });

  it("adds up a running total, and leaves out what's done", () => {
    // 2.55197 + 0.1 (contract) + 3 x 0.1 (agents) + 0.5 (fund) + 3 x 0.00125 (storage) + gas.
    expect(fmtNear(plan.total, 2)).toBe("3.48");
    const later = mainnetPlan({ owner: "hellbuddy.near", wasmBytes: 255197, done: { limits: true } });
    expect(later.total).toBe(plan.total - plan.steps[0].deposit - plan.steps[0].maxGasFee);
    expect(describeStep(later.steps[0])).toContain("[already done]");
  });

  it("prints signer, receiver, method, deposit and gas for a step", () => {
    const text = describeStep(plan.steps[5]);
    expect(text).toContain("signer:   hellbuddy.near");
    expect(text).toContain("receiver: limits.hellbuddy.near");
    expect(text).toContain("fund({})");
    expect(text).toContain("deposit 0.5000 NEAR");
    expect(text).toContain("gas 10 TGas");
    expect(text).toContain("running total:");
  });

  it("can skip the token rule", () => {
    expect(mainnetPlan({ owner: "hellbuddy.near", wasmBytes: 1, tokenRule: null }).steps.at(-1).id).toBe("storage-USDT");
  });
});
