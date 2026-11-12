import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { intentsClient } from "../src/intents.js";

// A NEAR Intents token list with a real SOL and a look-alike on another chain.
const LIST = [
  { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: 2.5 },
  { assetId: "nep141:sol.omft.near", symbol: "SOL", blockchain: "sol", decimals: 9, price: 81.25 },
  { assetId: "nep141:sol-fake.omft.near", symbol: "SOL", blockchain: "bsc", decimals: 9, price: 0.01 },
  { assetId: "nep141:usdc.near", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 },
];

function app() {
  const fetchImpl = (async () => new Response(JSON.stringify(LIST))) as unknown as typeof fetch;
  const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
  return buildApp({ cfg, chain: {} as never, receipts: {} as never, intents: intentsClient({ recipient: "x.testnet", fetchImpl }) });
}

describe("GET /v1/price/:symbol", () => {
  it("prices a token from NEAR Intents' list, on its home chain", async () => {
    const r = await app().inject("/v1/price/sol");
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ symbol: "SOL", usd: 81.25, blockchain: "sol", source: "NEAR Intents" });
  });

  it("reads $near as NEAR", async () => {
    const r = await app().inject("/v1/price/%24near");
    expect(r.json()).toMatchObject({ symbol: "NEAR", usd: 2.5 });
  });

  it("says no to a token that isn't listed", async () => {
    const r = await app().inject("/v1/price/toshi");
    expect(r.statusCode).toBe(404);
    expect(r.json().error).toMatch(/isn't on NEAR Intents' list/);
  });

  it("rejects something that isn't a symbol", async () => {
    expect((await app().inject("/v1/price/a")).statusCode).toBe(400);
  });
});

describe("GET /v1/tokens", () => {
  it("lists each symbol once, and NEAR as people type it", async () => {
    const r = await app().inject("/v1/tokens");
    expect(r.json().symbols).toEqual(["NEAR", "SOL", "USDC", "WNEAR"]);
  });
});

describe("GET /v1/fx", () => {
  const fx = async (q: string) => {
    const { ratesClient } = await import("../src/rates.js");
    const fetchImpl = (async () => new Response(JSON.stringify({ result: "success", time_last_update_utc: "today", rates: { USD: 1, INR: 88, EUR: 0.9 } }))) as unknown as typeof fetch;
    const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });
    return buildApp({ cfg, chain: {} as never, receipts: {} as never, rates: ratesClient({ fetchImpl }) }).inject(`/v1/fx?${q}`);
  };

  it("converts through the dollar", async () => {
    expect((await fx("amount=100&from=usd&to=inr")).json()).toMatchObject({ value: 8800, from: "USD", to: "INR" });
    expect((await fx("amount=90&from=eur&to=inr")).json().value).toBeCloseTo(8800);
  });

  it("says when it has no rate, and rejects nonsense", async () => {
    expect((await fx("amount=1&from=usd&to=xyz")).statusCode).toBe(404);
    expect((await fx("amount=abc&from=usd&to=inr")).statusCode).toBe(400);
  });
});
