import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { nearChain } from "./near.js";
import { fileStore } from "./receipts.js";
import { ownerActions } from "./owner.js";
import { intentsClient } from "./intents.js";
import { rheaClient } from "./rhea.js";
import { ratesClient } from "./rates.js";
import { checkOrders, fileOrders } from "./orders.js";
import { runCommand } from "./agent.js";

const cfg = loadConfig();
const deps = {
  cfg,
  chain: nearChain(cfg),
  receipts: fileStore(cfg.dataDir),
  owner: ownerActions(cfg),
  intents: intentsClient({ jwt: process.env.ONECLICK_JWT, recipient: process.env.AIRKEY_INTENTS_ACCOUNT ?? cfg.owner }),
  rates: ratesClient(),
  orders: fileOrders(cfg.dataDir),
  rhea: rheaClient({ network: cfg.network, rpc: cfg.rpc }),
};
const app = buildApp(deps);

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
await app.listen({ port: cfg.port, host: "0.0.0.0" });
console.log(`AIRKEY server on :${cfg.port} · ${cfg.network} · leash ${cfg.leash} · AI ${cfg.nearAi.apiKey ? "NEAR AI Cloud (private)" : cfg.openAi.apiKey ? `OpenAI ${cfg.openAi.model}` : "off"} · auth ${cfg.apiToken ? "on" : "off"}`);
