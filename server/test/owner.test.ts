import { createHash } from "node:crypto";
import { KeyPair, actions, createTransaction, encodeTransaction } from "near-api-js";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import { MAX_DAILY, checkOwnerArgs, ownerActions } from "../src/owner.js";

const cfg = loadConfig({ AIRKEY_OWNER: "o.testnet", NEAR_RPC: "http://127.0.0.1:9" });
const owner = ownerActions(cfg);
const kp = KeyPair.fromRandom("ed25519");

function build(signer: string, receiver: string, method: string, args: object = { id: 0 }) {
  const tx = createTransaction(signer, kp.getPublicKey(), receiver, 1n, [actions.functionCall(method, args, 50_000_000_000_000n, 1n)], new Uint8Array(32));
  const bytes = encodeTransaction(tx);
  const sig = kp.sign(createHash("sha256").update(bytes).digest()).signature;
  return { tx: Buffer.from(bytes).toString("base64"), signature: Buffer.from(sig).toString("base64") };
}

describe("owner relay", () => {
  it("refuses anything that isn't one owner call to the leash", async () => {
    const other = build("o.testnet", "someone-else.testnet", "approve");
    await expect(owner.submit(other.tx, other.signature)).rejects.toThrow("isn't a Keybots owner action");
    const notOwner = build("mallory.testnet", cfg.leash, "approve");
    await expect(owner.submit(notOwner.tx, notOwner.signature)).rejects.toThrow("isn't a Keybots owner action");
    const wrongMethod = build("o.testnet", cfg.leash, "remove_agent");
    await expect(owner.submit(wrongMethod.tx, wrongMethod.signature)).rejects.toThrow("isn't a Keybots owner action");
  });

  it("refuses a signature that doesn't match the key in the transaction", async () => {
    const good = build("o.testnet", cfg.leash, "approve");
    const forged = Buffer.from(KeyPair.fromRandom("ed25519").sign(new Uint8Array(32)).signature).toString("base64");
    await expect(owner.submit(good.tx, forged)).rejects.toThrow("doesn't match");
  });

  it("refuses methods outside the owner list before touching the chain", async () => {
    await expect(owner.prepare("remove_agent" as never, {}, kp.getPublicKey().toString())).rejects.toThrow("isn't an owner action");
  });
});

const N = 10n ** 24n;
const caps = (agent: string, tier: string, per: bigint, daily: bigint) => ({ agent, tier, per_payment_cap: per.toString(), daily_cap: daily.toString() });

describe("owner limits and withdraw", () => {
  it("lets the owner change an agent's limits, keeping its tier", () => {
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.trusted, "trusted", N / 2n, N))).not.toThrow();
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.untrusted, "untrusted", N / 10n, N / 5n))).not.toThrow();
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.trade, "trusted", N, 2n * N))).not.toThrow();
  });

  it("refuses other accounts, a changed tier, and limits that don't make sense", () => {
    expect(() => checkOwnerArgs(cfg, "add_agent", caps("drain.testnet", "trusted", 1n, 1n))).toThrow("your own three agents");
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.untrusted, "trusted", 1n, 1n))).toThrow("stays untrusted");
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.trusted, "trusted", 0n, N))).toThrow("more than zero");
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.trusted, "trusted", 2n * N, N))).toThrow("more than the daily");
    expect(() => checkOwnerArgs(cfg, "add_agent", caps(cfg.agents.trusted, "trusted", N, MAX_DAILY.testnet + 1n))).toThrow("at most 5 NEAR");
    expect(() => checkOwnerArgs(cfg, "add_agent", { ...caps(cfg.agents.trusted, "trusted", 1n, 1n), extra: 1 })).toThrow("Unexpected");
    expect(() => checkOwnerArgs(cfg, "add_agent", { ...caps(cfg.agents.trusted, "trusted", 1n, 1n), daily_cap: 5 })).toThrow("string of digits");
  });

  it("holds mainnet to a smaller daily limit", () => {
    const main = { ...cfg, network: "mainnet" as const };
    expect(() => checkOwnerArgs(main, "add_agent", caps(cfg.agents.trusted, "trusted", N / 10n, N / 2n))).not.toThrow();
    expect(() => checkOwnerArgs(main, "add_agent", caps(cfg.agents.trusted, "trusted", N / 10n, N))).toThrow("at most 0.5 NEAR");
  });

  it("withdraws only a positive amount, to the owner", () => {
    expect(() => checkOwnerArgs(cfg, "withdraw", { amount: (N / 10n).toString() })).not.toThrow();
    expect(() => checkOwnerArgs(cfg, "withdraw", { amount: "0" })).toThrow("more than zero");
    expect(() => checkOwnerArgs(cfg, "withdraw", { amount: "1", to: "drain.testnet" })).toThrow("Unexpected");
  });

  it("checks a signed limit change again before relaying it", async () => {
    const tampered = build("o.testnet", cfg.leash, "add_agent", caps(cfg.agents.trusted, "trusted", N, 100n * N));
    await expect(owner.submit(tampered.tx, tampered.signature)).rejects.toThrow("at most 5 NEAR");
  });
});
