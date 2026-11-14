import { buildApp, followsFor } from "./app.js";
import { fileFollows } from "./follows.js";
import { kallClient } from "./kall.js";
import { loadConfig } from "./config.js";
import { nearChain } from "./near.js";
import { outlayerChain } from "./outlayer.js";
import { fileStore } from "./receipts.js";
import { ownerActions } from "./owner.js";
import { intentsClient } from "./intents.js";
import { rheaClient } from "./rhea.js";
import { ratesClient } from "./rates.js";
import { checkOrders, fileOrders } from "./orders.js";
import { runCommand } from "./agent.js";
import { fileCalls } from "./calls.js";
import { fileVault } from "./vault.js";
import { telegramSource } from "./telegram.js";
import { attestations } from "./attest.js";

// server/.env (gitignored) for keys and switches, when it's there.
try {
  process.loadEnvFile(new URL("../.env", import.meta.url));
} catch {
  // No .env: the environment and keys/ are enough.
}
const cfg = loadConfig();
const deps = {
  cfg,
  chain: process.env.AIRKEY_SIGNER === "outlayer" ? outlayerChain(cfg, nearChain(cfg)) : nearChain(cfg),
  receipts: fileStore(cfg.dataDir),
  owner: ownerActions(cfg),
  intents: intentsClient({ jwt: process.env.ONECLICK_JWT, recipient: process.env.AIRKEY_INTENTS_ACCOUNT ?? cfg.owner }),
  rates: ratesClient(),
  orders: fileOrders(cfg.dataDir),
  rhea: rheaClient({ network: cfg.network, rpc: cfg.rpc }),
  calls: fileCalls(cfg.dataDir), // the calls book: calls.jsonl
  vault: fileVault(cfg.dataDir), // vault.json: what the app saves for the keyboard
  follows: fileFollows(cfg.dataDir), // follows.json and follow-trades.jsonl
  kall: kallClient(cfg.kallApi),
};
// Telegram: only with a bot token (TELEGRAM_BOT_TOKEN or keys/telegram.token). Read-only.
const telegram = telegramSource({ token: cfg.telegram.token, chatIds: cfg.telegram.chatIds, dataDir: cfg.dataDir });
telegram.start();
const followPoller = followsFor(deps);
const app = buildApp({ ...deps, followPoller, telegram });

// Watch the prices that orders are waiting on. A crossed order runs its command as the owner's own words.
const WATCH_MS = Number(process.env.AIRKEY_WATCH_MS ?? 15_000);
let looking = false;
setInterval(async () => {
  if (looking) return;
  looking = true;
  try {
    const fired = await checkOrders(
      deps.orders,
      (symbol) => deps.intents.price(symbol, WATCH_MS),
      async (command) => (await runCommand(deps, command, "typed")).id,
    );
    for (const o of fired) console.log(`order ${o.id}: ${o.symbol} ${o.direction} $${o.price} at $${o.triggeredPrice} -> ${o.command}`);
  } catch (e) {
    console.error(`order watcher: ${(e as Error).message}`);
  } finally {
    looking = false;
  }
}, WATCH_MS).unref();
// The KOLs the owner follows: their new calls on Kall, every minute. Only
// trades with AIRKEY_AUTO_TRADE=on; off, it records what it would have done.
const FOLLOW_MS = Number(process.env.AIRKEY_FOLLOW_MS ?? 60_000);
let following = false;
setInterval(async () => {
  if (following) return;
  following = true;
  try {
    for (const t of await followPoller.pollAll()) console.log(`follow @${t.handle} ${t.postId}: ${t.status} · ${t.message}`);
  } catch (e) {
    console.error(`follow poller: ${(e as Error).message}`);
  } finally {
    following = false;
  }
}, FOLLOW_MS).unref();
// Keep the slow lookups warm so the keyboard's chips come up fast: NEAR
// Intents' token list (refetched before it goes stale) and the leash's state.
// NEAR AI Cloud's hardware attestation, checked again once ten minutes old.
const warm = () => {
  deps.intents.tokens(4 * 60_000).catch(() => {});
  deps.chain.state().catch(() => {});
  attestations
    .refreshIfStale(cfg.nearAi)
    ?.then((r) => console.log(`NEAR AI attestation for ${r.model}: ${r.status} · ${r.detail}`))
    .catch(() => {});
};
warm();
setInterval(warm, 60_000).unref();

await app.listen({ port: cfg.port, host: process.env.HOST ?? "0.0.0.0" });
console.log(`Keybots server on :${cfg.port} · ${cfg.network} · leash ${cfg.leash} · AI ${cfg.nearAi.apiKey ? "NEAR AI Cloud (private)" : cfg.openAi.apiKey ? `OpenAI ${cfg.openAi.model}` : "off"} · auth ${cfg.apiToken ? "on" : "off"} · Telegram ${telegram.configured ? "on" : "off"}`);
