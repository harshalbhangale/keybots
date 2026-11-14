import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { RHEA } from "../src/rhea.js";

const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
const rhea = {
  network: RHEA.testnet,
  route: (s: string) => RHEA.testnet!.routes[s.toUpperCase()],
  quote: async (r: { decimals: number }) => (25n * 10n ** BigInt(r.decimals - 1)).toString(),
  holdings: async () => [],
};
const chain = (paused = false) => ({
  state: async () => ({ owner: "x.testnet", leash: "leash.x.testnet", paused, available: "1", agents: [{}, {}, {}], allowlist: [], blocklist: [], pending: [] }),
});
const xfeed = { feed: async () => ({ callers: [{}, {}], calls: [{}] }), caller: async () => [] };
const intents = { tokens: async () => [{ symbol: "NEAR" }, { symbol: "USDC" }] };

async function get(deps: Record<string, unknown>) {
  const app = buildApp({ cfg, receipts: {} as never, chain: chain() as never, ...deps } as never);
  const r = await app.inject({ method: "GET", url: "/v1/connected" });
  expect(r.statusCode).toBe(200);
  return r.json() as { services: { id: string; status: string; detail: string }[] };
}

describe("/v1/connected", () => {
  it("checks each service live and says what it saw", async () => {
    const { services } = await get({ rhea, xfeed, intents });
    const by = Object.fromEntries(services.map((s) => [s.id, s]));
    expect(by["spend-limits"]).toMatchObject({ status: "live", detail: `leash.x.testnet: ${Object.keys(cfg.agents).length} agents, running` });
    expect(by.rhea).toMatchObject({ status: "live" });
    expect(by.rhea.detail).toMatch(/^1 NEAR → 2\.50 USDC/);
    expect(by["near-intents"]).toMatchObject({ status: "live", detail: "2 tokens listed" });
    expect(by.x).toMatchObject({ status: "live", detail: "2 callers, 1 calls" });
    expect(by.telegram.status).toBe("off");
  });

  it("marks a service down when it fails, without failing the page", async () => {
    const { services } = await get({ chain: chain(true), intents: { tokens: async () => { throw new Error("502 from 1Click"); } }, xfeed });
    const by = Object.fromEntries(services.map((s) => [s.id, s]));
    expect(by["spend-limits"].detail).toBe("leash.x.testnet: everything is stopped");
    expect(by["near-intents"]).toMatchObject({ status: "down", detail: "502 from 1Click" });
    expect(by.rhea.status).toBe("off");
  });
});
