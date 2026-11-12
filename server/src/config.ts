import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

export interface Config {
  network: "testnet" | "mainnet";
  rpc: string;
  explorer: string;
  nearblocksApi: string;
  owner: string;
  leash: string;
  /** trusted: pays for what the owner types. untrusted: reads other people's words. trade: swaps, with its own caps. */
  agents: { trusted: string; untrusted: string; trade: string };
  keysDir: string;
  dataDir: string;
  /** Address book: name or alias -> NEAR account. */
  contacts: Record<string, string>;
  /** Bearer token clients must send. Empty means no auth (local dev only). */
  apiToken: string;
  nearAi: { apiKey: string; model: string; base: string };
  port: number;
}

/** "harshal=friend.x.testnet,harshal.near=friend.x.testnet" -> map */
export function parseContacts(s: string | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const pair of (s ?? "").split(",")) {
    const [k, v] = pair.split("=").map((x) => x?.trim().toLowerCase());
    if (k && v) out[k] = v;
  }
  return out;
}

export function loadConfig(env = process.env): Config {
  const network = env.NEAR_NETWORK === "mainnet" ? "mainnet" : "testnet";
  const owner = env.AIRKEY_OWNER ?? "airkey-harshal.testnet";
  return {
    network,
    rpc: env.NEAR_RPC ?? (network === "mainnet" ? "https://free.rpc.fastnear.com" : "https://test.rpc.fastnear.com"),
    explorer: network === "mainnet" ? "https://nearblocks.io" : "https://testnet.nearblocks.io",
    nearblocksApi: network === "mainnet" ? "https://api.nearblocks.io/v3" : "https://api-testnet.nearblocks.io/v3",
    owner,
    leash: env.AIRKEY_LEASH ?? `leash.${owner}`,
    agents: {
      trusted: env.AIRKEY_AGENT_TRUSTED ?? `pay.${owner}`,
      untrusted: env.AIRKEY_AGENT_UNTRUSTED ?? `inbox.${owner}`,
      trade: env.AIRKEY_AGENT_TRADE ?? `trade.${owner}`,
    },
    keysDir: env.AIRKEY_KEYS_DIR ?? join(ROOT, "keys"),
    dataDir: env.AIRKEY_DATA_DIR ?? join(ROOT, "server", "data"),
    contacts: parseContacts(
      env.AIRKEY_CONTACTS ??
        (network === "testnet"
          ? `harshal=friend.${owner},harshal.near=friend.${owner},friend=friend.${owner},vendor=vendor.${owner},designer=vendor.${owner},drain.near=drain.${owner},drain=drain.${owner}`
          : ""),
    ),
    apiToken: env.AIRKEY_API_TOKEN ?? "",
    nearAi: {
      apiKey: env.NEAR_AI_API_KEY ?? "",
      model: env.NEAR_AI_MODEL ?? "zai-org/GLM-5.1-FP8",
      base: env.NEAR_AI_BASE ?? "https://cloud-api.near.ai/v1",
    },
    port: Number(env.PORT ?? 8787),
  };
}
