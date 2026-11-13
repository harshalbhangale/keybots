import { describe as group, expect, it } from "vitest";
import { describe, readCommand } from "../src/agent.js";
import { readWithAi, toAction } from "../src/ai.js";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { parse } from "../src/parse.js";

const cfg = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: { apiKey: "", model: "m", base: "b" }, openAi: { apiKey: "", model: "m", base: "b" } };

group("describe", () => {
  it("gives a command the rules read back to the same action", () => {
    for (const text of ["pay harshal 0.2 for dinner", "swap 0.1 near to usdc", "swap $5 of near to usdc", "buy $2 of near", "sell 1 near if it drops below 2"]) {
      const action = parse(text);
      const d = describe(action)!;
      expect(parse(d.command)).toEqual(action);
    }
  });

  it("says it plainly, with the word for the hold", () => {
    expect(describe(parse("swap 5$ of near to usdc"))).toMatchObject({ title: "Swap $5 of NEAR to USDC", verb: "swap" });
    expect(describe(parse("buy $2 of near"))).toMatchObject({ title: "Buy $2 of NEAR", verb: "buy" });
    expect(describe(parse("pay harshal 0.2"))).toMatchObject({ title: "Pay 0.2 NEAR to harshal", verb: "pay" });
  });
});

group("reading", () => {
  it("uses the rules when they read it, and never calls an AI", async () => {
    let called = false;
    const deps = { cfg: { ...cfg, openAi: { apiKey: "k", model: "m", base: "b" } }, readAi: (async () => { called = true; throw new Error(); }) as never } as never;
    const r = await readCommand(deps, "swap $5 of near to usdc");
    expect(r.reader).toBe("rules");
    expect(called).toBe(false);
  });

  it("asks OpenAI for wording the rules miss, when only OpenAI is set up", async () => {
    const readAi = async (_t: string, ai: { provider: string }) => ({
      action: { kind: "swap" as const, amount: "5", from: "NEAR", to: "USDC", usd: true },
      evidence: { provider: ai.provider as "openai", model: "m", chatId: null, signature: { status: "unavailable" as const, algo: "ecdsa" as const }, attestation: "not checked" as const },
    });
    const deps = { cfg: { ...cfg, openAi: { apiKey: "k", model: "m", base: "b" } }, readAi } as never;
    const r = await readCommand(deps, "can you swap like five bucks of my near into usdc");
    expect(r.reader).toBe("openai");
    expect(describe(r.action)?.command).toBe("swap $5 of near to usdc");
  });

  it("reads dollar amounts the model returns", () => {
    expect(toAction('{"kind":"swap","amount_usd":"5","from":"near","to":"usdc"}')).toEqual({ kind: "swap", amount: "5", from: "NEAR", to: "USDC", usd: true });
  });

  it("OpenAI's answers aren't signature-checked", async () => {
    const urls: string[] = [];
    const fetchImpl = (async (u: string) => {
      urls.push(String(u));
      return new Response(JSON.stringify({ id: "chat1", model: "gpt", choices: [{ message: { content: '{"kind":"unknown"}' } }] }));
    }) as unknown as typeof fetch;
    const r = await readWithAi("hello", { provider: "openai", apiKey: "k", model: "m", base: "https://api" }, fetchImpl);
    expect(urls).toEqual(["https://api/chat/completions"]);
    expect(r.evidence).toMatchObject({ provider: "openai", signature: { status: "unavailable" } });
  });
});

group("POST /v1/read", () => {
  const app = () => buildApp({ cfg, chain: {} as never, receipts: {} as never });

  it("returns the chip and the exact command for the hold", async () => {
    const r = await app().inject({ method: "POST", url: "/v1/read", payload: { text: "swap 5$ of near to usdc" } });
    expect(r.json()).toEqual({ kind: "swap", title: "Swap $5 of NEAR to USDC", verb: "swap", command: "swap $5 of near to usdc", reader: "rules" });
  });

  it("says unknown for ordinary words, and needs text", async () => {
    expect((await app().inject({ method: "POST", url: "/v1/read", payload: { text: "see you at 7" } })).json()).toEqual({ kind: "unknown", reader: "rules" });
    expect((await app().inject({ method: "POST", url: "/v1/read", payload: {} })).statusCode).toBe(400);
  });
});
