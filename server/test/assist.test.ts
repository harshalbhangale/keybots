import { createHash } from "node:crypto";
import { privateKeyToAccount } from "viem/accounts";
import { describe as group, expect, it } from "vitest";
import { act, taskFor } from "../src/act.js";
import { aiReaders } from "../src/agent.js";
import { buildApp } from "../src/app.js";
import { KEPT_NOTE, MONEY_REFUSAL, ReplyLines, factsIn, languageName, looksLikeMoney, missingFacts, readAssistBody, tidy, type ReplyOption } from "../src/assist.js";
import { attestations } from "../src/attest.js";
import { loadConfig } from "../src/config.js";

const off = { apiKey: "", model: "m", base: "b" };
const base = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: off, openAi: off, serperKey: "" };
const near = { apiKey: "n", model: "qwen-test", base: "https://near" };
const openai = { apiKey: "o", model: "gpt", base: "https://openai" };
const both = { ...base, nearAi: near, openAi: openai, serperKey: "serper-test" };

// The enclave key that signs NEAR AI's answers in these tests.
const signer = privateKeyToAccount(`0x${"42".repeat(32)}`);
const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

type Answer = string[] | number | ((messages: { role: string; content: string }[]) => string[] | number);

/**
 * A fake network. Each chat answer streams back as server-sent events in
 * small byte pieces; NEAR AI signs "<model>:<sha256(request)>:<sha256(response)>"
 * over the exact bytes, as the real one does.
 */
function fakeNet(answers: { near?: Answer[]; openai?: Answer[]; serper?: unknown }) {
  const calls: { url: string; headers: Record<string, string>; body: any }[] = [];
  const signed = new Map<string, { req: string; res: Uint8Array }>();
  let n = 0;
  const impl = (async (u: string | URL, init?: RequestInit) => {
    const url = String(u);
    const headers = Object.fromEntries(Object.entries((init?.headers ?? {}) as Record<string, string>).map(([k, v]) => [k.toLowerCase(), v]));
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url, headers, body });
    if (url.includes("serper.dev")) return new Response(JSON.stringify(answers.serper ?? { organic: [] }));
    if (url.includes("/signature/")) {
      const id = url.split("/signature/")[1]!.split("?")[0]!;
      const s = signed.get(id);
      if (!s) return new Response("{}");
      const text = `${near.model}:${sha256(s.req)}:${sha256(s.res)}`;
      return new Response(JSON.stringify({ text, signature: await signer.signMessage({ message: text }), signing_address: signer.address, signature_kind: "provider_tee" }));
    }
    const which = url.startsWith("https://near") ? "near" : "openai";
    const queue = answers[which] ?? [];
    let a = queue.length > 1 ? queue.shift()! : queue[0];
    if (typeof a === "function") a = a(body.messages);
    if (a === undefined) a = 500;
    if (typeof a === "number") return new Response("{}", { status: a });
    const id = `${which}-${++n}`;
    const model = which === "near" ? near.model : openai.model;
    const text = a.map((t) => `data: ${JSON.stringify({ id, model, choices: [{ delta: { content: t } }] })}\n\n`).join("") + "data: [DONE]\n\n";
    const bytes = new TextEncoder().encode(text);
    if (which === "near") signed.set(id, { req: String(init!.body), res: bytes });
    // Seven bytes at a time, so lines and characters are split across reads.
    let i = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(c) {
        if (i >= bytes.length) return c.close();
        c.enqueue(bytes.slice(i, i + 7));
        i += 7;
      },
    });
    return new Response(stream, { headers: { "content-type": "text/event-stream" } });
  }) as unknown as typeof fetch;
  const chats = () => calls.filter((c) => c.url.endsWith("/chat/completions"));
  return { impl, calls, chats };
}

const appWith = (net: ReturnType<typeof fakeNet>, cfg = both) => buildApp({ cfg, chain: {} as never, receipts: {} as never, aiFetch: net.impl });

/** Posts to /v1/assist and reads the event stream back as a list. */
async function assist(net: ReturnType<typeof fakeNet>, payload: object, cfg = both) {
  const r = await appWith(net, cfg).inject({ method: "POST", url: "/v1/assist", payload });
  const events = r.body
    .split("\n\n")
    .filter(Boolean)
    .map((block) => {
      const event = block.match(/^event: (.+)$/m)?.[1];
      const data = block.match(/^data: (.+)$/m)?.[1];
      return { event: event!, data: data ? JSON.parse(data) : null };
    });
  const done = events.find((e) => e.event === "done")?.data;
  return { r, events, done, names: events.map((e) => e.event) };
}

group("POST /v1/assist: fix", () => {
  it("streams the fixed text, then done with a verified receipt", async () => {
    attestations.set({
      status: "verified",
      checkedAt: new Date().toISOString(),
      model: near.model,
      signingAddress: signer.address.toLowerCase(),
      gatewaySigningAddress: null,
      checks: { nonce: true, reportData: true, signerMatch: null, tdxQuote: "verified", nvidia: "verified", composeHash: true },
      detail: "test",
    });
    const net = fakeNet({ near: [["Can you send ", "the file by ", "tomorrow at 5pm?"]] });
    const { r, events, done, names } = await assist(net, { task: "fix", text: "can u send the file tmrw at 5pm" });
    expect(r.statusCode).toBe(200);
    expect(r.headers["content-type"]).toContain("text/event-stream");
    expect(names).toEqual(["chunk", "chunk", "chunk", "done"]);
    expect(events.filter((e) => e.event === "chunk").map((e) => e.data.t).join("")).toBe("Can you send the file by tomorrow at 5pm?");
    expect(done.task).toBe("fix");
    expect(done.text).toBe("Can you send the file by tomorrow at 5pm?");
    expect(done.note).toBeUndefined();
    expect(done.receipt).toMatchObject({
      provider: "near-ai-cloud",
      model: near.model,
      signature: "verified",
      attestation: "verified",
      checks: { tdxQuote: "verified", nvidia: "verified", nonce: true, signerMatch: true, composeHash: true },
    });
    expect(typeof done.receipt.ms).toBe("number");
    // Streamed, unaliased, and the signature fetched for this answer.
    const [chat] = net.chats();
    expect(chat!.body.stream).toBe(true);
    expect(chat!.headers["x-no-aliasing"]).toBe("true");
    expect(chat!.body.messages[1].content).toBe("can u send the file tmrw at 5pm");
    expect(net.calls.some((c) => c.url.includes("/signature/near-"))).toBe(true);
  });

  it("says mismatch when the signed text isn't over these bytes", async () => {
    const net = fakeNet({ near: [["Hello."]] });
    const real = net.impl;
    const tampered = (async (u: string | URL, init?: RequestInit) => {
      const r = await real(u, init);
      if (!String(u).includes("/signature/")) return r;
      const j = await r.json();
      const text = `${near.model}:${"0".repeat(64)}:${"0".repeat(64)}`;
      return new Response(JSON.stringify({ ...j, text, signature: await signer.signMessage({ message: text }) }));
    }) as typeof fetch;
    const { done } = await assist({ ...net, impl: tampered }, { task: "fix", text: "hello" });
    expect(done.receipt.signature).toBe("mismatch");
  });
});

group("POST /v1/assist: shorter, warmer, formal", () => {
  for (const [task, word] of [["shorter", "shorter"], ["warmer", "warmer"], ["formal", "formal"]] as const) {
    it(`${task}: streams the rewrite with its own prompt`, async () => {
      const net = fakeNet({ near: [["Running late, ", "there at 7."]] });
      const { done, names } = await assist(net, { task, text: "hey so im running a bit late but ill be there at 7 ok" });
      expect(names.at(-1)).toBe("done");
      expect(names).toContain("chunk");
      expect(done.text).toBe("Running late, there at 7.");
      expect(net.chats()[0]!.body.messages[0].content).toContain(word);
    });
  }
});

group("POST /v1/assist: facts check", () => {
  const text = "pay day is 15 march, mail ana@corp.io or ping @ana_k, link https://corp.io/pay";
  const good = "Payday is 15 March. Mail ana@corp.io or ping @ana_k. Link: https://corp.io/pay";

  it("asks once more when a fact is dropped, and takes the second answer", async () => {
    const net = fakeNet({ near: [["Payday is in March. Mail ana@corp.io or ping @ana_k. Link: https://corp.io/pay"], [good]] });
    const { done, names } = await assist(net, { task: "fix", text });
    expect(net.chats()).toHaveLength(2);
    expect(net.chats()[1]!.body.messages[0].content).toContain("15");
    expect(done.text).toBe(good);
    expect(done.note).toBeUndefined();
    // The second try isn't streamed: the client already has the first.
    expect(names.filter((n) => n === "chunk")).toHaveLength(1);
  });

  it("sends the person's own words back when the second answer drops one too", async () => {
    const net = fakeNet({ near: [["Payday is in March, mail Ana."]] });
    const { done } = await assist(net, { task: "warmer", text });
    expect(net.chats()).toHaveLength(2);
    expect(done.text).toBe(text);
    expect(done.note).toBe(KEPT_NOTE);
    expect(done.receipt.provider).toBe("near-ai-cloud");
  });

  it("finds numbers, links, emails, handles and accounts, but not texting shorthand", () => {
    expect(factsIn("see u 2moro at 5pm, gr8! b4 then send 1,250 to bob.testnet, @kim, kim@x.co www.x.co/a.").sort()).toEqual(
      ["1250", "5", "@kim", "bob.testnet", "kim@x.co", "www.x.co/a"].sort(),
    );
    expect(missingFacts("meet at 7:30 on 3rd", "Meet at 7:30 on the 3rd.")).toEqual([]);
    expect(missingFacts("costs 10000", "It costs 10,000.")).toEqual([]);
    expect(missingFacts("call 15 people", "Call 5 people.")).toEqual(["15"]);
    expect(missingFacts("ping @Ana", "Ping @ana.")).toEqual([]);
  });
});

group("POST /v1/assist: reply", () => {
  it("sends each option as soon as its line is complete, then done with all three", async () => {
    const net = fakeNet({ near: [["YES: Sure, see ", "you at 7!\nNOT NOW: Can't tonight, ", "maybe next week?\nASK: What time ", "works for you?"]] });
    const { events, done, names } = await assist(net, { task: "reply", text: "dinner tonight?", source: "copied" });
    expect(names).toEqual(["option", "option", "option", "done"]);
    const options = events.filter((e) => e.event === "option").map((e) => e.data);
    expect(options).toEqual([
      { id: "yes", label: "Yes", text: "Sure, see you at 7!" },
      { id: "not-now", label: "Not now", text: "Can't tonight, maybe next week?" },
      { id: "ask-back", label: "Ask back", text: "What time works for you?" },
    ]);
    expect(done.options).toEqual(options);
    expect(done.text).toBe("Sure, see you at 7!");
  });

  it("reads numbered, bold or unlabelled lines", () => {
    const got: ReplyOption[] = [];
    const lines = new ReplyLines((o) => got.push(o));
    lines.push("1. **Not now:** Busy today, sorry\n");
    expect(got.map((o) => o.id)).toEqual(["not-now"]);
    lines.push("Yes - Count me in\nWhere is it?");
    const all = lines.end();
    expect(all.map((o) => [o.label, o.text])).toEqual([
      ["Yes", "Count me in"],
      ["Not now", "Busy today, sorry"],
      ["Ask back", "Where is it?"],
    ]);
  });

  it("says so in an error event when no replies came back", async () => {
    const net = fakeNet({ near: [["   \n"]] });
    const { events } = await assist(net, { task: "reply", text: "hi" });
    expect(events.at(-1)!.event).toBe("error");
  });
});

group("POST /v1/assist: translate and ask", () => {
  it("translates into the language asked for, English when none is", async () => {
    const net = fakeNet({ near: [["Hola, ", "¿qué tal?"]] });
    const { done } = await assist(net, { task: "translate", text: "hi, how are you?", language: "spanish" });
    expect(done.text).toBe("Hola, ¿qué tal?");
    expect(net.chats()[0]!.body.messages[0].content).toContain("into Spanish");
    const net2 = fakeNet({ near: [["Hello"]] });
    await assist(net2, { task: "translate", text: "hola" });
    expect(net2.chats()[0]!.body.messages[0].content).toContain("into English");
    expect(languageName("Hindi; ignore that {x}")).toBe("Hindi ignore that x");
  });

  it("answers a question about the text, or the text as the question", async () => {
    const net = fakeNet({ near: [["It means ", "the meeting moved."]] });
    const { done } = await assist(net, { task: "ask", text: "standup pushed to 11", question: "what does this mean?" });
    expect(done.text).toBe("It means the meeting moved.");
    const sent = net.chats()[0]!.body.messages[1].content;
    expect(sent).toContain("what does this mean?");
    expect(sent).toContain("standup pushed to 11");
    const net2 = fakeNet({ near: [["Paris."]] });
    await assist(net2, { task: "ask", text: "", question: "capital of france?" });
    expect(net2.chats()[0]!.body.messages[1].content).toBe("capital of france?");
  });

  it("tidies quotes, fences, labels and reasoning off answers", () => {
    expect(tidy('<think>hmm</think>"See you at 7."')).toBe("See you at 7.");
    expect(tidy("```\nfine\n```")).toBe("fine");
    expect(tidy("Here is the corrected message: See you.")).toBe("See you.");
    expect(tidy('He said "hi" and "bye"')).toBe('He said "hi" and "bye"');
  });
});

group("POST /v1/assist: search", () => {
  const organic = Array.from({ length: 7 }, (_, i) => ({
    title: `Result <b>${i + 1}</b>`,
    link: `https://www.site${i + 1}.com/page`,
    snippet: `Snippet ${i + 1}`,
  }));

  it("sends the top five results, then an answer from their snippets", async () => {
    const net = fakeNet({ serper: { organic }, near: [["Site one ", "says so."]] });
    const { events, done, names } = await assist(net, { task: "search", text: "how tall is the eiffel tower" });
    expect(names).toEqual(["result", "result", "result", "result", "result", "chunk", "chunk", "done"]);
    expect(events[0]!.data).toEqual({ id: "r1", title: "Result 1", url: "https://www.site1.com/page", site: "site1.com", snippet: "Snippet 1" });
    const serper = net.calls.find((c) => c.url.includes("serper.dev"))!;
    expect(serper.headers["x-api-key"]).toBe("serper-test");
    expect(serper.body).toEqual({ q: "how tall is the eiffel tower", num: 5 });
    const prompt = net.chats()[0]!.body.messages[1].content;
    expect(prompt).toContain("Snippet 5");
    expect(prompt).not.toContain("Snippet 6");
    expect(done.text).toBe("Site one says so.");
    expect(done.results).toHaveLength(5);
    expect(done.receipt.provider).toBe("near-ai-cloud");
  });

  it("is 503 without a Serper key, and an error event when nothing is found", async () => {
    const net = fakeNet({ near: [["x"]] });
    const r = await appWith(net, { ...both, serperKey: "" }).inject({ method: "POST", url: "/v1/assist", payload: { task: "search", text: "x" } });
    expect(r.statusCode).toBe(503);
    expect(net.calls).toHaveLength(0);
    const { events } = await assist(fakeNet({ serper: { organic: [] } }), { task: "search", text: "zzqx" });
    expect(events).toEqual([{ event: "error", data: { error: "Search found nothing for that." } }]);
  });
});

group("POST /v1/assist: money", () => {
  const money = [
    "send 5 near to bob.testnet",
    "pay harshal 0.5 near for dinner",
    "swap 20 usdc to sol",
    "buy $10 of near",
    "$SOL is going to moon, buying now",
    "can you transfer $40 to 0x1111111111111111111111111111111111111111 today",
    "please send ₹500 to ravi@okaxis",
  ];

  it("refuses money with 409 and asks no AI", async () => {
    for (const text of money) {
      const net = fakeNet({ near: [["x"]] });
      const r = await appWith(net).inject({ method: "POST", url: "/v1/assist", payload: { task: "fix", text } });
      expect(r.statusCode, text).toBe(409);
      expect(r.json()).toEqual({ error: MONEY_REFUSAL, money: true });
      expect(net.calls).toHaveLength(0);
    }
    const net = fakeNet({ near: [["x"]] });
    const r = await appWith(net).inject({ method: "POST", url: "/v1/assist", payload: { task: "ask", text: "my note", question: "send 2 near to amy.testnet" } });
    expect(r.statusCode).toBe(409);
    expect(net.calls).toHaveLength(0);
  });

  it("lets ordinary messages through", () => {
    for (const text of ["see you near the station at 7", "lunch was $12, my treat", "mail me at ana@corp.io", "I owe you one", "pay attention in class"]) {
      expect(looksLikeMoney(text), text).toBe(false);
    }
  });
});

group("POST /v1/assist: requests and fallback", () => {
  it("needs a known task and 1 to 2,000 characters", async () => {
    const net = fakeNet({});
    for (const payload of [{}, { task: "fix" }, { task: "fix", text: "  " }, { task: "delete", text: "hi" }, { task: "fix", text: "a".repeat(2001) }]) {
      expect((await appWith(net).inject({ method: "POST", url: "/v1/assist", payload })).statusCode).toBe(400);
    }
    expect(net.calls).toHaveLength(0);
    expect(readAssistBody({ task: "fix", text: "a".repeat(2000) }).ok).toBe(true);
  });

  it("is 503 when no AI is set up", async () => {
    const r = await appWith(fakeNet({}), base).inject({ method: "POST", url: "/v1/assist", payload: { task: "fix", text: "hi" } });
    expect(r.statusCode).toBe(503);
  });

  it("falls back to OpenAI when NEAR AI Cloud fails, and says so in the receipt", async () => {
    const net = fakeNet({ near: [503], openai: [["Hi there."]] });
    const { done } = await assist(net, { task: "fix", text: "hi there" });
    expect(done.text).toBe("Hi there.");
    expect(done.receipt).toMatchObject({ provider: "openai", model: "gpt", signature: "unavailable", attestation: "not checked" });
    expect(done.receipt.checks).toBeUndefined();
    expect(net.chats().map((c) => c.url)).toEqual(["https://near/chat/completions", "https://openai/chat/completions"]);
    expect(net.chats()[1]!.headers["x-no-aliasing"]).toBeUndefined();
    expect(net.calls.some((c) => c.url.includes("/signature/"))).toBe(false);
  });

  it("asks no one else when the fallback is off", async () => {
    const net = fakeNet({ near: [503], openai: [["Hi there."]] });
    const { events } = await assist(net, { task: "fix", text: "hi there" }, { ...both, aiFallback: "off" });
    expect(events).toEqual([{ event: "error", data: { error: "The AI didn't answer. Try again in a moment." } }]);
    expect(net.chats().map((c) => c.url)).toEqual(["https://near/chat/completions"]);
  });
});

group("POST /v1/act", () => {
  it("keeps its shape: text, provider, model, signature, attestation", async () => {
    const net = fakeNet({ openai: [["Running late, ", "there in 10."]] });
    const r = await appWith(net, { ...both, nearAi: off }).inject({ method: "POST", url: "/v1/act", payload: { text: "running late there in 10", action: "rewrite" } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ text: "Running late, there in 10.", provider: "openai", model: "gpt", signature: "unavailable", attestation: "not checked" });
  });

  it("maps rewrite to fix, tone to warmer, and reply to the first reply", async () => {
    expect(taskFor({ text: "x", action: "rewrite" })).toBe("fix");
    expect(taskFor({ text: "x", action: "tone", tone: "friendly" })).toBe("warmer");
    expect(taskFor({ text: "x", action: "tone", tone: "formal" })).toBe("formal");
    expect(taskFor({ text: "x", action: "translate" })).toBe("translate");
    const net = fakeNet({ near: [["YES: Sure!\nNOT NOW: Not today.\nASK: When?"]] });
    const r = await act({ text: "coffee?", action: "reply" }, aiReaders(both), net.impl);
    expect(r).toMatchObject({ text: "Sure!", provider: "near-ai-cloud", model: near.model, signature: "verified" });
  });

  it("needs text and a known action; 503 with no AI; 502 when the AI fails; 409 for money", async () => {
    const net = fakeNet({ openai: [500] });
    for (const payload of [{}, { text: "   ", action: "rewrite" }, { text: "hi" }, { text: "hi", action: "delete" }]) {
      expect((await appWith(net).inject({ method: "POST", url: "/v1/act", payload })).statusCode).toBe(400);
    }
    expect((await appWith(net, base).inject({ method: "POST", url: "/v1/act", payload: { text: "hi", action: "ask" } })).statusCode).toBe(503);
    const failed = await appWith(net, { ...both, nearAi: off }).inject({ method: "POST", url: "/v1/act", payload: { text: "hi", action: "ask" } });
    expect(failed.statusCode).toBe(502);
    const paid = await appWith(net).inject({ method: "POST", url: "/v1/act", payload: { text: "send 5 near to bob.testnet", action: "rewrite" } });
    expect(paid.statusCode).toBe(409);
    expect(paid.json().money).toBe(true);
  });
});
