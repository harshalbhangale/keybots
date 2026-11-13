import { describe as group, expect, it } from "vitest";
import { aiReaders } from "../src/agent.js";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { memoryGlyfs, parseBuilt } from "../src/ai-glyfs.js";
import { OptionStream, REWRITE_STYLES, keepsExact, keepsNumbers, looksLikeRewrite, parseRewriteOptions, rewriteTarget } from "../src/ai-rewrite.js";
import { stripTags } from "../src/ai-search.js";
import { ThinkFilter, streamChat } from "../src/ai-stream.js";
import { needsTidy, readsAsMoney, suggestByRules } from "../src/ai-suggest.js";
import { chooseTarget, latinLanguage, parseTranslation, scriptLanguage } from "../src/ai-translate.js";

const off = { apiKey: "", model: "m", base: "b" };
const base = { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: off, openAi: off };
const near = { apiKey: "n", model: "glm", base: "https://near" };
const openai = { apiKey: "o", model: "gpt", base: "https://openai" };

type Answer = string | number | { pieces: string[]; breakAfter?: number };

/** A streamed chat completion, the way both AIs send one. */
function sse(which: string, pieces: string[], breakAfter?: number): Response {
  const enc = new TextEncoder();
  const queue = pieces.slice(0, breakAfter ?? pieces.length);
  const body = new ReadableStream<Uint8Array>({
    pull(c) {
      const p = queue.shift();
      if (p !== undefined) {
        c.enqueue(enc.encode(`data: ${JSON.stringify({ id: `${which}-1`, model: which === "near" ? "glm" : "gpt", choices: [{ delta: { content: p } }] })}\n\n`));
      } else if (breakAfter !== undefined) {
        c.error(new Error("cut"));
      } else {
        c.enqueue(enc.encode("data: [DONE]\n\n"));
        c.close();
      }
    },
  });
  return new Response(body, { headers: { "content-type": "text/event-stream" } });
}

/** A fake network: each AI answers as told (streamed or whole, as asked); search engines answer `search`. */
function fakeFetch(answers: { near?: Answer; openai?: Answer; search?: unknown }) {
  const urls: string[] = [];
  const bodies: { which: string; messages: { role: string; content: string }[]; stream: boolean }[] = [];
  const impl = (async (u: string | URL, init?: RequestInit) => {
    const url = String(u);
    urls.push(url);
    if (url.includes("brave.com") || url.includes("serper.dev")) return new Response(JSON.stringify(answers.search ?? {}));
    const which = url.startsWith("https://near") ? "near" : "openai";
    if (url.includes("/signature/")) return new Response("{}");
    const body = JSON.parse(String(init?.body));
    bodies.push({ which, ...body });
    const a = answers[which];
    if (a === undefined) return new Response("{}", { status: 500 });
    if (typeof a === "number") return new Response("{}", { status: a });
    const pieces = typeof a === "string" ? [a] : a.pieces;
    if (body.stream) return sse(which, pieces, typeof a === "string" ? undefined : a.breakAfter);
    return new Response(JSON.stringify({ id: `${which}-1`, model: which === "near" ? "glm" : "gpt", choices: [{ message: { content: pieces.join("") } }] }));
  }) as unknown as typeof fetch;
  return { impl, urls, bodies };
}

/** The events of one SSE reply, in order. */
function events(payload: string): { event: string; data: any }[] {
  return payload
    .split("\n\n")
    .filter((b) => b.trim())
    .map((b) => {
      const [e, d] = b.split("\n");
      return { event: e.replace("event: ", ""), data: JSON.parse(d.replace("data: ", "")) };
    });
}

function app(f: ReturnType<typeof fakeFetch>, over: Partial<typeof base> = {}, searchEnv = {}) {
  const glyfs = memoryGlyfs();
  const a = buildApp({ cfg: { ...base, openAi: openai, ...over }, chain: {} as never, receipts: {} as never, aiFetch: f.impl, glyfs, searchEnv });
  return { a, glyfs };
}

const versions = '{"basic":"Can you send the file by 6?","work":"Could you please send the file by 6?","polite":"Would you mind sending the file by 6?","shorter":"File by 6?","emoji":"Can you send the file by 6? 🙏"}';

group("streamed chat", () => {
  it("asks NEAR AI Cloud first and checks its signature over the stream", async () => {
    const f = fakeFetch({ near: { pieces: ["Hel", "lo"] }, openai: "nope" });
    const got: string[] = [];
    const r = await streamChat([{ role: "user", content: "hi" }], aiReaders({ ...base, nearAi: near, openAi: openai }), { fetchImpl: f.impl, onToken: (t) => got.push(t) });
    expect(r.content).toBe("Hello");
    expect(got.join("")).toBe("Hello");
    expect(r.evidence.provider).toBe("near-ai-cloud");
    expect(f.urls).toEqual(["https://near/chat/completions", "https://near/signature/near-1?signing_algo=ecdsa"]);
  });

  it("starts over with OpenAI when NEAR AI Cloud stops midway", async () => {
    const f = fakeFetch({ near: { pieces: ["Hel", "lo"], breakAfter: 1 }, openai: "Hi there" });
    let restarts = 0;
    const r = await streamChat([{ role: "user", content: "hi" }], aiReaders({ ...base, nearAi: near, openAi: openai }), { fetchImpl: f.impl, onRestart: () => restarts++ });
    expect(r.content).toBe("Hi there");
    expect(r.evidence.provider).toBe("openai");
    expect(restarts).toBe(1);
  });

  it("never asks OpenAI when the fallback is off", async () => {
    const f = fakeFetch({ near: 503, openai: "nope" });
    await expect(streamChat([{ role: "user", content: "hi" }], aiReaders({ ...base, nearAi: near, openAi: openai, aiFallback: "off" }), { fetchImpl: f.impl })).rejects.toThrow("NEAR AI Cloud answered 503");
    expect(f.urls).toEqual(["https://near/chat/completions"]);
  });

  it("holds back a model's thinking, even split across pieces", () => {
    let out = "";
    const filter = new ThinkFilter((t) => (out += t));
    for (const p of ["<thi", "nk>hmm</th", "ink>Hello", " there <", "3"]) filter.push(p);
    filter.flush();
    expect(out).toBe("Hello there <3");
  });
});

group("rewrite versions", () => {
  it("picks each version out the moment it is finished", () => {
    const got: string[] = [];
    const s = new OptionStream(REWRITE_STYLES, "can u send file b4 6", (o) => got.push(o.id));
    for (let i = 0; i < versions.length; i += 7) s.push(versions.slice(i, i + 7));
    expect(got).toEqual(["basic", "work", "polite", "shorter", "emoji"]);
  });

  it("drops a version that lost a number or a link", () => {
    expect(keepsNumbers("meet at 7", "Let's meet at seven.")).toBe(true);
    expect(keepsNumbers("meet at 7", "Let's meet later.")).toBe(false);
    expect(keepsExact("see https://a.b/c now", "Please see https://a.b/c now.")).toBe(true);
    expect(keepsExact("see https://a.b/c now", "Please see a.b now.")).toBe(false);
    expect(parseRewriteOptions('{"basic":"Hi.","work":""}').map((o) => o.id)).toEqual(["basic"]);
    expect(parseRewriteOptions('{"basic":"Hi.","work":"Hel').map((o) => o.id)).toEqual(["basic"]);
  });

  it("never offers the model's working as the rewrite", () => {
    expect(looksLikeRewrite("We need to rewrite the message in each style.", "hi")).toBe(false);
    expect(looksLikeRewrite("See you at Jake's.", "see u at jakes")).toBe(true);
    expect(rewriteTarget("fix grammar: need the files asap")).toBe("need the files asap");
  });
});

group("POST /v1/act/stream", () => {
  it("streams rewrite versions as options, then done with who answered", async () => {
    const f = fakeFetch({ openai: { pieces: [versions.slice(0, 40), versions.slice(40)] } });
    const r = await app(f).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "can u send file b4 6", action: "rewrite" } });
    expect(r.headers["content-type"]).toBe("text/event-stream");
    const ev = events(r.payload);
    expect(ev.filter((e) => e.event === "option").map((e) => e.data.id)).toEqual(["basic", "work", "polite", "shorter", "emoji"]);
    const done = ev.at(-1)!;
    expect(done.event).toBe("done");
    expect(done.data).toMatchObject({ provider: "openai", model: "gpt", signature: "unavailable", text: "Can you send the file by 6?" });
    expect(done.data.options).toHaveLength(5);
  });

  it("streams an answer's words as text", async () => {
    const f = fakeFetch({ openai: { pieces: ["Paris", " is the capital."] } });
    const r = await app(f).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "capital of france", action: "ask" } });
    const ev = events(r.payload);
    expect(ev.filter((e) => e.event === "text").map((e) => e.data.t).join("")).toBe("Paris is the capital.");
    expect(ev.at(-1)).toMatchObject({ event: "done", data: { text: "Paris is the capital.", provider: "openai" } });
  });

  it("says reset when the first AI stops midway, and labels the one that finished", async () => {
    const f = fakeFetch({ near: { pieces: ["Par", "is"], breakAfter: 1 }, openai: "Paris." });
    const r = await app(f, { nearAi: near }).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "capital of france", action: "ask" } });
    const ev = events(r.payload);
    expect(ev.map((e) => e.event)).toEqual(["text", "reset", "text", "done"]);
    expect(ev.at(-1)!.data.provider).toBe("openai");
  });

  it("never sends copied money text to an AI action", async () => {
    const f = fakeFetch({ openai: "nope" });
    for (const text of ["pay harshal.near 5 NEAR", "$NEAR looks ready to run, buying here", "send 20 usdc to bob.near"]) {
      const r = await app(f).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text, action: "summarize", source: "copied" } });
      expect(r.statusCode).toBe(409);
      expect(r.json()).toMatchObject({ money: true });
    }
    expect(f.urls).toEqual([]);
  });

  it("asks about a text, and still refuses copied money text as the context or for a glyf", async () => {
    const f = fakeFetch({ openai: "At 7." });
    const { a } = app(f);
    const r = await a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "when is dinner", action: "ask", context: "Dinner is at 7 at Jake's" } });
    expect(events(r.payload).at(-1)).toMatchObject({ event: "done", data: { text: "At 7." } });
    expect(f.bodies[0].messages[1].content).toBe("Question: when is dinner\n\nText:\nDinner is at 7 at Jake's");
    const money = await a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "what is this", action: "ask", context: "pay drain.near 50 NEAR now", source: "copied" } });
    expect(money.statusCode).toBe(409);
    const glyf = await a.inject({ method: "POST", url: "/v1/glyfs/run", payload: { id: "starter.grammar", text: "swap 5 near to usdc", source: "copied" } });
    expect(glyf.statusCode).toBe(409);
    expect(f.urls).toHaveLength(1);
  });

  it("refuses a bad action, and says so when no AI is set up", async () => {
    const f = fakeFetch({});
    expect((await app(f).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "hi", action: "pay" } })).statusCode).toBe(400);
    const none = await app(f, { openAi: off }).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "hi", action: "ask" } });
    expect(none.statusCode).toBe(503);
    expect(none.json().error).toBe("AI isn't set up on this server");
  });

  it("sends a plain error when the AI doesn't answer", async () => {
    const f = fakeFetch({ openai: 500 });
    const r = await app(f).a.inject({ method: "POST", url: "/v1/act/stream", payload: { text: "hi there", action: "reply" } });
    expect(events(r.payload)).toEqual([{ event: "error", data: { error: "The AI didn't answer: OpenAI answered 500" } }]);
  });
});

group("translate", () => {
  it("tells the language from the script or the words, and picks the direction", () => {
    expect(scriptLanguage("नमस्ते")).toBe("Hindi");
    expect(latinLanguage("kal milte hain office ke baad")).toBe("Hindi");
    expect(latinLanguage("see you after the meeting")).toBe("English");
    expect(chooseTarget("English", { text: "", primary: "English", secondary: "Hindi" })).toBe("Hindi");
    expect(chooseTarget("Spanish", { text: "", primary: "English", secondary: "Hindi" })).toBe("English");
    expect(parseTranslation('{"detected":"hinglish","target":"English","translation":" See you tomorrow "}', { text: "", primary: "English", secondary: "Hindi" })).toEqual({ detected: "Hindi", target: "English", translation: "See you tomorrow" });
  });

  it("POST /v1/translate translates into the picked language, labels who answered, and remembers it", async () => {
    const f = fakeFetch({ openai: '{"detected":"English","target":"Spanish","translation":"Nos vemos mañana"}' });
    const { a } = app(f);
    const r = await a.inject({ method: "POST", url: "/v1/translate", payload: { text: "see you tomorrow", target: "Spanish" } });
    expect(r.json()).toMatchObject({ detected: "English", target: "Spanish", translation: "Nos vemos mañana", provider: "openai" });
    await a.inject({ method: "POST", url: "/v1/translate", payload: { text: "see you tomorrow", target: "Spanish" } });
    expect(f.urls).toHaveLength(1);
  });
});

group("suggest", () => {
  it("never offers a chip for money or a crypto call", async () => {
    for (const t of ["pay harshal.near 5", "swap 5 near to usdc", "send 3 near to bob.near pls", "$NEAR about to pump, buy now"]) {
      expect(readsAsMoney(t)).toBe(true);
      expect(suggestByRules(t)).toBeNull();
    }
    const f = fakeFetch({ openai: '{"intent":"rewrite"}' });
    const r = await app(f).a.inject({ method: "POST", url: "/v1/suggest", payload: { text: "pay harshal.near 5 near thx" } });
    expect(r.json()).toEqual({ suggestion: null, reader: "rules" });
    expect(f.urls).toEqual([]);
  });

  it("reads rough messages, questions and write-asks by rules", () => {
    expect(needsTidy("hey can u send me the file b4 lunch")).toBe(true);
    expect(readsAsMoney("hey can u send me the file b4 lunch")).toBe(false);
    expect(suggestByRules("im gonna be late sry traffic is bad")).toMatchObject({ action: "rewrite", label: "Tidy this up" });
    expect(suggestByRules("why is the sky blue")).toMatchObject({ action: "ask" });
    expect(suggestByRules("write a birthday message for my mom")).toMatchObject({ action: "write" });
    expect(suggestByRules("See you at the office tomorrow.")).toBeNull();
  });

  it("asks a model only when the rules can't tell", async () => {
    const f = fakeFetch({ openai: '{"intent":"rewrite"}' });
    const r = await app(f).a.inject({ method: "POST", url: "/v1/suggest", payload: { text: "kal milte hain office ke baad yaar" } });
    expect(r.json()).toMatchObject({ suggestion: { action: "rewrite" }, reader: "openai" });
  });
});

group("search", () => {
  it('says "Search needs a key" when there is none', async () => {
    const f = fakeFetch({});
    const { a } = app(f);
    const r = await a.inject({ method: "POST", url: "/v1/search", payload: { query: "near protocol" } });
    expect(r.statusCode).toBe(501);
    expect(r.json()).toEqual({ error: "Search needs a key", needsKey: true });
    expect((await a.inject({ method: "GET", url: "/v1/ai/status" })).json()).toEqual({ ai: ["openai"], search: null });
    expect(f.urls).toEqual([]);
  });

  it("returns Brave results as plain-text cards", async () => {
    const f = fakeFetch({ search: { web: { results: [{ title: "<strong>NEAR</strong> Protocol", url: "https://www.near.org/", description: "The <b>chain</b> &amp; more" }, { title: "bad", url: "javascript:alert(1)" }] } } });
    const r = await app(f, {}, { BRAVE_SEARCH_KEY: "k" }).a.inject({ method: "POST", url: "/v1/search", payload: { query: "near" } });
    expect(r.json()).toEqual({ provider: "brave", answer: null, cards: [{ id: "brave-0", title: "NEAR Protocol", url: "https://www.near.org/", domain: "near.org", snippet: "The chain & more" }] });
    expect(stripTags("a <b>b</b> &quot;c&quot;")).toBe('a b "c"');
  });

  it("returns Serper's answer box and results", async () => {
    const f = fakeFetch({ search: { answerBox: { title: "France", answer: "Paris", link: "https://en.wikipedia.org/wiki/Paris" }, organic: [{ title: "Paris", link: "https://paris.fr/", snippet: "City" }] } });
    const r = await app(f, {}, { SERPER_API_KEY: "k" }).a.inject({ method: "POST", url: "/v1/search", payload: { query: "capital of france" } });
    expect(r.json()).toMatchObject({ provider: "google", answer: { value: "Paris", source: "en.wikipedia.org" }, cards: [{ domain: "paris.fr" }] });
  });

  it("searches YouTube videos, and keeps only YouTube links", async () => {
    const f = fakeFetch({
      search: {
        videos: [
          { title: "Dune: Part Two | Official Trailer", link: "https://www.youtube.com/watch?v=Way9Dexny3w", channel: "Warner Bros.", duration: "2:25", date: "May 3, 2023" },
          { title: "Elsewhere", link: "https://evil.example/watch?v=1", channel: "x" },
          { title: "Fake", link: "https://youtube.com.evil.example/watch?v=1" },
        ],
      },
    });
    const r = await app(f, {}, { SERPER_API_KEY: "k" }).a.inject({ method: "POST", url: "/v1/search", payload: { query: "dune 2 trailer", kind: "youtube" } });
    expect(f.urls.some((u) => u.endsWith("/videos"))).toBe(true);
    expect(r.json()).toEqual({
      provider: "youtube",
      answer: null,
      cards: [{ id: "youtube-0", title: "Dune: Part Two | Official Trailer", url: "https://www.youtube.com/watch?v=Way9Dexny3w", domain: "Warner Bros. · 2:25", snippet: "May 3, 2023" }],
    });
  });

  it("says YouTube needs the Serper key", async () => {
    const r = await app(fakeFetch({}), {}, {}).a.inject({ method: "POST", url: "/v1/search", payload: { query: "x", kind: "youtube" } });
    expect(r.statusCode).toBe(501);
  });
});

group("my glyfs", () => {
  it("saves, lists, replaces by name, and removes", async () => {
    const { a } = app(fakeFetch({}));
    const made = (await a.inject({ method: "POST", url: "/v1/glyfs", payload: { name: "Pirate", prompt: "Rewrite it like a pirate." } })).json();
    expect(made).toMatchObject({ name: "Pirate", prompt: "Rewrite it like a pirate." });
    const again = (await a.inject({ method: "POST", url: "/v1/glyfs", payload: { name: "pirate", prompt: "Arr, pirate it." } })).json();
    expect(again.id).toBe(made.id);
    const list = (await a.inject({ method: "GET", url: "/v1/glyfs" })).json();
    expect(list.glyfs).toHaveLength(1);
    expect(list.starters.length).toBeGreaterThan(3);
    expect((await a.inject({ method: "POST", url: "/v1/glyfs", payload: { name: "", prompt: "x" } })).statusCode).toBe(400);
    expect((await a.inject({ method: "DELETE", url: `/v1/glyfs/${made.id}` })).json()).toEqual({ ok: true });
    expect((await a.inject({ method: "DELETE", url: `/v1/glyfs/${made.id}` })).statusCode).toBe(404);
  });

  it("builds one from a description without saving it", async () => {
    const f = fakeFetch({ openai: '```json\n{"name":"Pirate talk","prompt":"Rewrite it the way a pirate would say it."}\n```' });
    const { a, glyfs } = app(f);
    const r = await a.inject({ method: "POST", url: "/v1/glyfs/build", payload: { description: "make it sound like a pirate" } });
    expect(r.json()).toMatchObject({ name: "Pirate talk", prompt: "Rewrite it the way a pirate would say it.", provider: "openai" });
    expect(glyfs.list()).toEqual([]);
    expect(parseBuilt("no json here")).toBeNull();
  });

  it("runs a saved glyf on the text, streamed, with the glyf's job in the prompt", async () => {
    const f = fakeFetch({ openai: { pieces: ["Arr, ", "see ye at 7."] } });
    const { a, glyfs } = app(f);
    const g = glyfs.save("Pirate", "Rewrite it like a pirate.");
    const r = await a.inject({ method: "POST", url: "/v1/glyfs/run", payload: { id: g.id, text: "see you at 7" } });
    const ev = events(r.payload);
    expect(ev.at(-1)).toMatchObject({ event: "done", data: { text: "Arr, see ye at 7.", provider: "openai", glyf: "Pirate" } });
    expect(f.bodies[0].messages[0].content).toContain("Your job: Rewrite it like a pirate.");
    expect(f.bodies[0].messages[1].content).toBe("see you at 7");
    expect((await a.inject({ method: "POST", url: "/v1/glyfs/run", payload: { id: "nope", text: "hi" } })).statusCode).toBe(404);
  });
});
