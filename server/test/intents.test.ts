import { describe, expect, it } from "vitest";
import { intentsClient, pickToken, toUnits, type IntentsToken } from "../src/intents.js";

const LIST: IntentsToken[] = [
  { assetId: "nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1", symbol: "USDC", blockchain: "near", decimals: 6, price: 1 },
  { assetId: "nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near", symbol: "USDC", blockchain: "sol", decimals: 6, price: 1 },
  { assetId: "nep141:sol.omft.near", symbol: "SOL", blockchain: "sol", decimals: 9, price: 81 },
  { assetId: "1cs_v1:aptos:aptos-fa:0x0d82", symbol: "SOL", blockchain: "aptos", decimals: 8, price: 81 },
  { assetId: "nep141:wrap.near", symbol: "wNEAR", blockchain: "near", decimals: 24, price: 3.38 },
  { assetId: "nep141:eth-0x6982.omft.near", symbol: "PEPE", blockchain: "eth", decimals: 18, price: 0.000004 },
];

describe("token check", () => {
  it("pays from NEAR and receives on the token's home chain", () => {
    expect(pickToken(LIST, "usdc", "from").token?.blockchain).toBe("near");
    const sol = pickToken(LIST, "sol", "to");
    expect(sol.verified).toBe(true);
    expect(sol.token?.assetId).toBe("nep141:sol.omft.near");
    expect(sol.alsoOn).toEqual(["aptos"]);
  });

  it("reads NEAR as wNEAR", () => {
    expect(pickToken(LIST, "near", "from").token?.assetId).toBe("nep141:wrap.near");
  });

  it("uses the only listing when there's one", () => {
    expect(pickToken(LIST, "pepe", "to").token?.blockchain).toBe("eth");
  });

  it("refuses symbols NEAR Intents doesn't list", () => {
    const fake = pickToken(LIST, "TOSHI2", "to");
    expect(fake.verified).toBe(false);
    expect(fake.reason).toMatch(/isn't on NEAR Intents' list of 6/);
  });
});

describe("toUnits", () => {
  it("is exact", () => {
    expect(toUnits("20", 6)).toBe("20000000");
    expect(toUnits("0.5", 24)).toBe("500000000000000000000000");
    expect(() => toUnits("0.1234567", 6)).toThrow(/Too many decimals/);
  });
});

describe("quote", () => {
  it("asks 1Click for a dry run with exact units and returns the quote", async () => {
    let sent: Record<string, unknown> = {};
    const fakeFetch = (async (url: string, init?: RequestInit) => {
      if (String(url).endsWith("/tokens")) return new Response(JSON.stringify(LIST));
      sent = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ quote: { amountIn: "20000000", amountInFormatted: "20.0", amountInUsd: "19.99", amountOut: "245495298", amountOutFormatted: "0.245495298", amountOutUsd: "19.91", minAmountOut: "243040345", timeEstimate: 10 } }));
    }) as typeof fetch;
    const c = intentsClient({ recipient: "o.testnet", fetchImpl: fakeFetch });
    const from = (await c.pick("usdc", "from")).token!;
    const to = (await c.pick("sol", "to")).token!;
    const q = await c.quote(from, to, "20");
    expect(sent.dry).toBe(true);
    expect(sent.amount).toBe("20000000");
    expect(sent.originAsset).toBe(from.assetId);
    expect(q.amountOutFormatted).toBe("0.245495298");
    expect(q.dry).toBe(true);
  });
});

describe("live swaps", () => {
  it("asks for a deposit address on NEAR, refunds on NEAR, and pays NEAR tokens out on NEAR", async () => {
    let sent: Record<string, unknown> = {};
    const fakeFetch = (async (url: string, init?: RequestInit) => {
      if (String(url).endsWith("/tokens")) return new Response(JSON.stringify(LIST));
      sent = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ quote: { amountIn: "20000000", amountInFormatted: "20.0", amountOut: "1", amountOutFormatted: "1", depositAddress: "abc123", deadline: "soon" } }));
    }) as typeof fetch;
    const c = intentsClient({ recipient: "o.testnet", fetchImpl: fakeFetch });
    const usdc = (await c.pick("usdc", "from")).token!;
    const near = (await c.pick("near", "to")).token!;
    const q = await c.liveQuote(usdc, near, "20", { refundTo: "me.near", recipient: "me.near" });
    expect(sent.dry).toBe(false);
    expect(sent.depositType).toBe("ORIGIN_CHAIN");
    expect(sent.refundTo).toBe("me.near");
    expect(sent.recipientType).toBe("DESTINATION_CHAIN");
    expect(q.depositAddress).toBe("abc123");
    expect(q.dry).toBe(false);
  });

  it("keeps tokens from other chains inside NEAR Intents for you", async () => {
    let sent: Record<string, unknown> = {};
    const fakeFetch = (async (url: string, init?: RequestInit) => {
      if (String(url).endsWith("/tokens")) return new Response(JSON.stringify(LIST));
      sent = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ quote: { amountIn: "1", amountInFormatted: "1", amountOut: "1", amountOutFormatted: "1", depositAddress: "d" } }));
    }) as typeof fetch;
    const c = intentsClient({ recipient: "o.testnet", fetchImpl: fakeFetch });
    await c.liveQuote((await c.pick("usdc", "from")).token!, (await c.pick("sol", "to")).token!, "1", { refundTo: "me.near", recipient: "me.near" });
    expect(sent.recipientType).toBe("INTENTS");
  });

  it("refuses a live quote without a deposit address", async () => {
    const fakeFetch = (async (url: string) =>
      String(url).endsWith("/tokens") ? new Response(JSON.stringify(LIST)) : new Response(JSON.stringify({ quote: { amountIn: "1" } }))) as typeof fetch;
    const c = intentsClient({ recipient: "o.testnet", fetchImpl: fakeFetch });
    await expect(c.liveQuote((await c.pick("usdc", "from")).token!, (await c.pick("sol", "to")).token!, "1", { refundTo: "a", recipient: "a" })).rejects.toThrow(/no deposit address/);
  });

  it("reads a finished swap's status and its explorer links", async () => {
    const fakeFetch = (async () =>
      new Response(JSON.stringify({
        status: "SUCCESS",
        swapDetails: { amountOutFormatted: "0.58", originChainTxHashes: [{ explorerUrl: "https://nearblocks.io/txns/a" }], destinationChainTxHashes: [{ explorerUrl: "https://nearblocks.io/txns/b" }] },
      }))) as typeof fetch;
    const s = await intentsClient({ recipient: "x", fetchImpl: fakeFetch }).status("abc");
    expect(s.done).toBe(true);
    expect(s.amountOutFormatted).toBe("0.58");
    expect(s.txs).toEqual(["https://nearblocks.io/txns/a", "https://nearblocks.io/txns/b"]);
  });

  it("treats a swap still waiting for its deposit as not done", async () => {
    const fakeFetch = (async () => new Response(JSON.stringify({ status: "PENDING_DEPOSIT", swapDetails: {} }))) as typeof fetch;
    expect((await intentsClient({ recipient: "x", fetchImpl: fakeFetch }).status("abc")).done).toBe(false);
  });
});
