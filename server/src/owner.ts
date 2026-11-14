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

export const OWNER_METHODS = ["approve", "reject", "set_paused", "allow", "disallow", "block", "unblock", "add_agent", "withdraw"] as const;
export type OwnerMethod = (typeof OWNER_METHODS)[number];

const YOCTO = 10n ** 24n;
/** The most a daily limit may be set to from the phone: a slip of the finger can't open the whole balance. */
export const MAX_DAILY = { testnet: 5n * YOCTO, mainnet: YOCTO / 2n } as const;

const yocto = (v: unknown, what: string): bigint => {
  if (typeof v !== "string" || !/^\d{1,39}$/.test(v)) throw new UserError(`${what} must be yoctoNEAR, as a string of digits`);
  return BigInt(v);
};

/**
 * What the owner may sign from the phone, checked before it's built and again
 * before it's relayed. add_agent only changes the caps of one of this server's
 * agents, keeping its tier; withdraw only sends NEAR back to the owner.
 */
export function checkOwnerArgs(cfg: Pick<Config, "agents" | "network">, method: string, args: Record<string, unknown>) {
  if (method === "add_agent") {
    const tiers: Record<string, string> = { [cfg.agents.trusted]: "trusted", [cfg.agents.untrusted]: "untrusted", [cfg.agents.trade]: "trusted" };
    const tier = tiers[String(args.agent)];
    if (!tier) throw new UserError("Only the limits of your own three agents can be changed here");
    if (args.tier !== tier) throw new UserError(`${String(args.agent)} stays ${tier}; only its limits change here`);
    const per = yocto(args.per_payment_cap, "per_payment_cap");
    const daily = yocto(args.daily_cap, "daily_cap");
    if (per <= 0n) throw new UserError("The per-payment limit must be more than zero");
    if (per > daily) throw new UserError("The per-payment limit can't be more than the daily limit");
    const max = MAX_DAILY[cfg.network === "mainnet" ? "mainnet" : "testnet"];
    if (daily > max) throw new UserError(`The daily limit can be at most ${Number(max / 10n ** 18n) / 1e6} NEAR here`);
    if (Object.keys(args).some((k) => !["agent", "tier", "per_payment_cap", "daily_cap"].includes(k))) throw new UserError("Unexpected arguments");
  }
  if (method === "withdraw") {
    if (yocto(args.amount, "amount") <= 0n) throw new UserError("Withdraw more than zero");
    if (Object.keys(args).some((k) => k !== "amount")) throw new UserError("Unexpected arguments");
  }
}
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
      checkOwnerArgs(cfg, method, args);
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
      const only = tx.actions.length === 1 ? (tx.actions[0] as { functionCall?: { methodName: string; args: Uint8Array } }).functionCall : undefined;
      if (tx.signerId !== cfg.owner || tx.receiverId !== cfg.leash || !only || !OWNER_METHODS.includes(only.methodName as OwnerMethod)) {
        throw new UserError("That isn't a Keybots owner action.");
      }
      let sent: Record<string, unknown>;
      try {
        sent = JSON.parse(Buffer.from(only.args).toString("utf8") || "{}");
      } catch {
        throw new UserError("That isn't a Keybots owner action.");
      }
      checkOwnerArgs(cfg, only.methodName, sent);
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
