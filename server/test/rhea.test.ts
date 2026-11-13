import { describe, expect, it } from "vitest";
import { RHEA, amountOut, fromUnits, minOut, rheaClient, sellMsg, sellRoute, swapMsg, toUnits } from "../src/rhea.js";

const net = RHEA.testnet!;

describe("rhea", () => {
  it("knows the testnet pools and nothing on mainnet", () => {
    const c = rheaClient({ network: "testnet", rpc: "x" });
    expect(c.route("usdt")?.pool).toBe(1084);
    expect(c.route("sol")).toBeUndefined();
    expect(rheaClient({ network: "mainnet", rpc: "x" }).route("usdt")).toBeUndefined();
  });

  it("builds a one-pool swap with a floor", () => {
    const route = net.routes.USDT;
    const msg = JSON.parse(swapMsg(net, route, "100", minOut("1000")));
    expect(msg.actions[0]).toEqual({ pool_id: 1084, token_in: "wrap.testnet", token_out: "usdt.itachicara.testnet", amount_in: "100", min_amount_out: "990" });
  });

  it("reads what Rhea paid out from its log", () => {
    const logs = ["EVENT_JSON:{}", "Swapped 100000000000000000000000 wrap.testnet for 124112944945096337934249 usdt.itachicara.testnet, total fee 30, admin fee 6"];
    expect(amountOut(logs, "usdt.itachicara.testnet")).toBe("124112944945096337934249");
    expect(amountOut(logs, "usdc.itachicara.testnet")).toBeUndefined();
    expect(fromUnits("124112944945096337934249", 24)).toBe("0.1241");
  });

  it("knows how to sell the tokens the leash holds", () => {
    expect(sellRoute(net, "usdc", "near")).toMatchObject({ pool: 1103, unwrap: true, to: { symbol: "NEAR", token: "wrap.testnet" } });
    expect(sellRoute(net, "USDT", "NEAR")).toMatchObject({ pool: 1084, unwrap: true });
    // One pool for both directions.
    expect(sellRoute(net, "usdc", "usdt")).toMatchObject({ pool: 1126, unwrap: false, to: { symbol: "USDT", token: "usdt.itachicara.testnet" } });
    expect(sellRoute(net, "usdt", "usdc")).toMatchObject({ pool: 1126, from: { symbol: "USDT" }, to: { symbol: "USDC" } });
    expect(sellRoute(net, "near", "usdc")).toBeUndefined();
    expect(sellRoute(net, "usdc", "sol")).toBeUndefined();
    expect(sellRoute(net, "usdc", "usdc")).toBeUndefined();
    expect(rheaClient({ network: "mainnet", rpc: "x" }).sellRoute("usdc", "near")).toBeUndefined();
    // The routes Builder 1 reads keep their shape.
    expect(net.routes.USDC).toEqual({ symbol: "USDC", token: "usdc.itachicara.testnet", pool: 1103, decimals: 24 });
  });

  it("builds the sale Rhea runs, with a floor", () => {
    const msg = JSON.parse(sellMsg(sellRoute(net, "usdc", "near")!, "500", minOut("1000")));
    expect(msg.actions).toEqual([{ pool_id: 1103, token_in: "usdc.itachicara.testnet", token_out: "wrap.testnet", amount_in: "500", min_amount_out: "990" }]);
  });

  it("turns typed amounts into token units exactly", () => {
    expect(toUnits("0.5", 24)).toBe("500000000000000000000000");
    expect(toUnits("3", 6)).toBe("3000000");
    expect(() => toUnits("0.1234567", 6)).toThrow();
    expect(() => toUnits("abc", 6)).toThrow();
  });

  it("asks the pool what a sale returns", async () => {
    let args: Record<string, unknown> = {};
    const fetchImpl = (async (_u: string, init?: RequestInit) => {
      args = JSON.parse(Buffer.from(JSON.parse(String(init?.body)).params.args_base64, "base64").toString());
      return new Response(JSON.stringify({ result: { result: [...Buffer.from(JSON.stringify("77"))] } }));
    }) as unknown as typeof fetch;
    const c = rheaClient({ network: "testnet", rpc: "https://rpc", fetchImpl });
    expect(await c.quoteSell(c.sellRoute("usdc", "usdt")!, "100")).toBe("77");
    expect(args).toEqual({ pool_id: 1126, token_in: "usdc.itachicara.testnet", amount_in: "100", token_out: "usdt.itachicara.testnet" });
  });

  it("asks the pool for a quote over RPC", async () => {
    let sent: { params?: { account_id?: string; method_name?: string; args_base64?: string } } = {};
    const fetchImpl = (async (_u: string, init?: RequestInit) => {
      sent = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({ result: { result: [...Buffer.from(JSON.stringify("124"))] } }));
    }) as unknown as typeof fetch;
    const c = rheaClient({ network: "testnet", rpc: "https://rpc", fetchImpl });
    expect(await c.quote(net.routes.USDT, "100")).toBe("124");
    expect(sent.params?.account_id).toBe("ref-finance-101.testnet");
    expect(sent.params?.method_name).toBe("get_return");
    expect(JSON.parse(Buffer.from(sent.params!.args_base64!, "base64").toString()).pool_id).toBe(1084);
  });
});
