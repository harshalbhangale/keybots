import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { nearChain } from "./near.js";
import { fileStore } from "./receipts.js";
import { ownerActions } from "./owner.js";

const cfg = loadConfig();
const app = buildApp({ cfg, chain: nearChain(cfg), receipts: fileStore(cfg.dataDir), owner: ownerActions(cfg) });
await app.listen({ port: cfg.port, host: "0.0.0.0" });
console.log(`AIRKEY server on :${cfg.port} · ${cfg.network} · leash ${cfg.leash} · NEAR AI ${cfg.nearAi.apiKey ? "on" : "off"} · auth ${cfg.apiToken ? "on" : "off"}`);
