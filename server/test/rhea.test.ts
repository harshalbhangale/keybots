import { describe, expect, it } from "vitest";
import { RHEA, amountOut, fromUnits, minOut, rheaClient, swapMsg } from "../src/rhea.js";

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
