// Owner actions signed on the phone. The server builds the transaction, the
// phone signs its hash with the owner's key (behind Face ID), and the server
// only relays it. The owner's key never reaches the server.
import { createHash } from "node:crypto";
import {
  JsonRpcProvider,
  KeyType,
  PublicKey,
  Signature,
  SignedTransaction,
  actions,
  baseDecode,
  createTransaction,
  decodeTransaction,
  encodeTransaction,
} from "near-api-js";
import type { Config } from "./config.js";

export const OWNER_METHODS = ["approve", "reject", "set_paused", "allow", "disallow", "block", "unblock"] as const;
export type OwnerMethod = (typeof OWNER_METHODS)[number];
const GAS = 50_000_000_000_000n;

export interface Prepared {
  tx: string; // base64 borsh Transaction
  hash: string; // base64 sha256 of tx: what the phone signs
  summary: string;
}

export function ownerActions(cfg: Config) {
  const provider = new JsonRpcProvider({ url: cfg.rpc });

  return {
    async prepare(method: OwnerMethod, args: Record<string, unknown>, publicKey: string): Promise<Prepared> {
      if (!OWNER_METHODS.includes(method)) throw new UserError(`${method} isn't an owner action`);
      const pk = PublicKey.fromString(publicKey);
      let key: { nonce: bigint | number; permission: unknown };
      try {
        key = (await provider.viewAccessKey({ accountId: cfg.owner, publicKey: pk, finalityQuery: { finality: "final" } })) as never;
      } catch {
        throw new UserError(`This device's key isn't on ${cfg.owner}. Enroll it first (scripts/add-device-key.mjs).`);
      }
      if (key.permission !== "FullAccess") throw new UserError("This device's key isn't a full-access key for the owner.");
      const block = (await provider.viewBlock({ finality: "final" })) as { header: { hash: string } };
      const tx = createTransaction(cfg.owner, pk, cfg.leash, BigInt(key.nonce) + 1n, [actions.functionCall(method, args, GAS, 1n)], baseDecode(block.header.hash));
      const bytes = encodeTransaction(tx);
      return {
        tx: Buffer.from(bytes).toString("base64"),
        hash: createHash("sha256").update(bytes).digest("base64"),
        summary: `${cfg.owner} → ${cfg.leash}.${method}(${JSON.stringify(args)})`,
      };
    },

    async submit(txB64: string, signatureB64: string) {
      const bytes = new Uint8Array(Buffer.from(txB64, "base64"));
      const tx = decodeTransaction(bytes);
      // Relay only what prepare() would have built: one owner call to the leash.
      const only = tx.actions.length === 1 ? (tx.actions[0] as { functionCall?: { methodName: string } }).functionCall : undefined;
      if (tx.signerId !== cfg.owner || tx.receiverId !== cfg.leash || !only || !OWNER_METHODS.includes(only.methodName as OwnerMethod)) {
        throw new UserError("That isn't an Keybots owner action.");
      }
      const sig = new Uint8Array(Buffer.from(signatureB64, "base64"));
      const hash = createHash("sha256").update(bytes).digest();
      if (!tx.publicKey.verify(hash, sig)) throw new UserError("The signature doesn't match this device's key.");
      const signed = new SignedTransaction({ transaction: tx, signature: new Signature({ keyType: KeyType.ED25519, data: sig }) });
      const res = (await provider.sendTransaction(signed)) as {
        transaction: { hash: string };
        status: { SuccessValue?: string; Failure?: unknown };
        receipts_outcome: { outcome: { logs: string[] } }[];
      };
      const v = res.status?.SuccessValue;
      let result: unknown = null;
      if (v) {
        try {
          result = JSON.parse(Buffer.from(v, "base64").toString());
        } catch {
          result = null;
        }
      }
      const events = res.receipts_outcome
        .flatMap((o) => o.outcome.logs)
        .filter((l) => l.startsWith("EVENT_JSON:"))
        .map((l) => JSON.parse(l.slice(11)));
      return { method: only.methodName, txHash: res.transaction.hash, url: `${cfg.explorer}/txns/${res.transaction.hash}`, ok: !res.status?.Failure, result, events };
    },
  };
}

export class UserError extends Error {}
