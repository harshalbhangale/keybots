import { existsSync, readFileSync } from "node:fs";
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
  /** Used for reading only when NEAR AI Cloud isn't set up. The key lives in the env or keys/openai.key, never in git. */
  openAi: { apiKey: string; model: string; base: string };
  /** "openai" (default): OpenAI answers when NEAR AI Cloud can't. "off": NEAR AI Cloud or nothing (the demo recording). */
  aiFallback: "openai" | "off";
  /** Mainnet spends real money: no swap above this many dollars, whatever the command says. */
  mainnetUsdCap: number;
  /** Kall Markets' API, where the calls of the KOLs you follow come from. */
  kallApi: string;
  /** Trades for KOLs you follow only run when AIRKEY_AUTO_TRADE=on. Off, the server still says what it would have done. */
  autoTrade: boolean;
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
      trade: env.AIRKEY_AGENT_TRADE ?? `trader.${owner}`,
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
      apiKey: env.NEAR_AI_API_KEY ?? keyFile(join(env.AIRKEY_KEYS_DIR ?? join(ROOT, "keys"), "near-ai.key")),
      model: env.NEAR_AI_MODEL ?? "Qwen/Qwen3-VL-30B-A3B-Instruct",
      base: env.NEAR_AI_BASE ?? "https://cloud-api.near.ai/v1",
    },
    openAi: {
      apiKey: env.OPENAI_API_KEY ?? keyFile(join(env.AIRKEY_KEYS_DIR ?? join(ROOT, "keys"), "openai.key")),
      model: env.OPENAI_MODEL ?? "gpt-4.1-mini",
      base: env.OPENAI_BASE ?? "https://api.openai.com/v1",
    },
    aiFallback: env.AIRKEY_AI_FALLBACK === "off" ? "off" : "openai",
    mainnetUsdCap: Number(env.AIRKEY_MAINNET_USD_CAP ?? 0.15),
    kallApi: env.KALL_API ?? "https://kallmarkets.vercel.app",
    autoTrade: env.AIRKEY_AUTO_TRADE === "on",
    port: Number(env.PORT ?? 8787),
  };
}

/** A secret kept in a file (keys/ is gitignored); empty when there isn't one. */
function keyFile(path: string): string {
  try {
    return existsSync(path) ? readFileSync(path, "utf8").trim() : "";
  } catch {
    return "";
  }
}
