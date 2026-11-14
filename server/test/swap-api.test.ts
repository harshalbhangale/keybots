import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { RHEA } from "../src/rhea.js";

const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
const rhea = {
  network: RHEA.testnet,
  route: (s: string) => RHEA.testnet!.routes[s.toUpperCase()],
  quote: async () => "124112944945096337934249",
  holdings: async () => [{ symbol: "USDT", token: "usdt.itachicara.testnet", amount: "0.1241" }],
};
const chain = { state: async () => ({ owner: "x.testnet", leash: "leash.x.testnet", paused: false, available: "1", agents: [], allowlist: [], blocklist: [], pending: [] }) };
const app = () => buildApp({ cfg, chain: chain as never, receipts: { list: () => [] } as never, rhea: rhea as never });

describe("swap API", () => {
  it("quotes NEAR into a token Rhea has a pool for, with the floor", async () => {
    const r = await app().inject("/v1/swap/quote?amount=0.1&to=usdt");
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ venue: "Rhea", pool: 1084, to: "USDT", amountIn: "0.1", amountOut: "0.1241", minAmountOut: "0.1228" });
  });

  it("says no for tokens without a pool and for bad amounts", async () => {
    expect((await app().inject("/v1/swap/quote?amount=0.1&to=sol")).statusCode).toBe(404);
    expect((await app().inject("/v1/swap/quote?amount=abc&to=usdt")).statusCode).toBe(400);
  });

  it("lists what the leash holds with its state", async () => {
    const r = await app().inject("/v1/state");
    expect(r.json().holdings).toEqual([{ symbol: "USDT", token: "usdt.itachicara.testnet", amount: "0.1241" }]);
  });
});
