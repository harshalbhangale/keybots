import { createHash } from "node:crypto";
import { KeyPair, actions, createTransaction, encodeTransaction } from "near-api-js";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import { ownerActions } from "../src/owner.js";

const cfg = loadConfig({ AIRKEY_OWNER: "o.testnet", NEAR_RPC: "http://127.0.0.1:9" });
const owner = ownerActions(cfg);
const kp = KeyPair.fromRandom("ed25519");

function build(signer: string, receiver: string, method: string) {
  const tx = createTransaction(signer, kp.getPublicKey(), receiver, 1n, [actions.functionCall(method, { id: 0 }, 50_000_000_000_000n, 1n)], new Uint8Array(32));
  const bytes = encodeTransaction(tx);
  const sig = kp.sign(createHash("sha256").update(bytes).digest()).signature;
  return { tx: Buffer.from(bytes).toString("base64"), signature: Buffer.from(sig).toString("base64") };
}

describe("owner relay", () => {
  it("refuses anything that isn't one owner call to the leash", async () => {
    const other = build("o.testnet", "someone-else.testnet", "approve");
    await expect(owner.submit(other.tx, other.signature)).rejects.toThrow("isn't an Keybots owner action");
    const notOwner = build("mallory.testnet", cfg.leash, "approve");
    await expect(owner.submit(notOwner.tx, notOwner.signature)).rejects.toThrow("isn't an Keybots owner action");
    const wrongMethod = build("o.testnet", cfg.leash, "withdraw");
    await expect(owner.submit(wrongMethod.tx, wrongMethod.signature)).rejects.toThrow("isn't an Keybots owner action");
  });

  it("refuses a signature that doesn't match the key in the transaction", async () => {
    const good = build("o.testnet", cfg.leash, "approve");
    const forged = Buffer.from(KeyPair.fromRandom("ed25519").sign(new Uint8Array(32)).signature).toString("base64");
    await expect(owner.submit(good.tx, forged)).rejects.toThrow("doesn't match");
  });

  it("refuses methods outside the owner list before touching the chain", async () => {
    await expect(owner.prepare("withdraw" as never, {}, kp.getPublicKey().toString())).rejects.toThrow("isn't an owner action");
  });
});
