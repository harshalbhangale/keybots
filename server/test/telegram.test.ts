// The Telegram source, offline: a fake Bot API (no network) feeding the poller.
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { fakeKall } from "../src/kall.js";
import { TOKEN, fakeBotApi, group, privateGroup, person, T0 } from "./telegram-fake.js";
import { cleanToken, readAsCall, telegramSource, tidyText } from "../src/telegram.js";

afterEach(() => vi.restoreAllMocks());

describe("reading updates", () => {
  it("keeps spot calls, advances the offset and asks Telegram the way the Bot API wants", async () => {
    const api = fakeBotApi();
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    api.queue.push(
      api.msg(group, { message_id: 1, from: person, text: "$SOL looks strong, buying here" }),
      api.msg(group, { message_id: 2, from: person, text: "good morning all" }),
    );
    expect(await tg.pollOnce(25)).toBe(2);
    expect(api.requests[0]).toMatchObject({ method: "getUpdates", body: { offset: 0, timeout: 25, allowed_updates: ["message", "channel_post"] } });
    expect(api.requests[0]!.url).toBe(`https://api.telegram.org/bot${TOKEN}/getUpdates`);
    // The next ask starts after the last update: nothing is handled twice.
    expect(await tg.pollOnce(25)).toBe(0);
    expect(api.requests[1]!.body.offset).toBe(102);
    expect(tg.calls()).toHaveLength(1);
    expect(tg.calls()[0]).toEqual({
      id: "tg--100200-1",
      chatId: "-100200",
      chatTitle: "Alpha Calls",
      from: { username: "sol_sam", first_name: "Sam" },
      date: T0,
      text: "$SOL looks strong, buying here",
      url: "https://t.me/alphacalls/1",
      asset: "SOL",
      direction: "buy",
    });
  });

  it("ignores bots, empty and long text, private chats, stickers and edits; reads channel posts", async () => {
    const api = fakeBotApi();
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    const buy = "$SOL buying here";
    api.queue.push(
      api.msg(group, { message_id: 1, from: { ...person, is_bot: true }, text: buy }),
      api.msg(group, { message_id: 2, from: person, text: "   " }),
      api.msg(group, { message_id: 3, from: person, text: `${buy} ${"x".repeat(1500)}` }),
      api.msg({ id: 7, type: "private", first_name: "Sam" }, { message_id: 4, from: person, text: buy }),
      api.msg(group, { message_id: 5, from: person, sticker: {} }),
      api.msg(group, { message_id: 6, from: person, text: buy }, "edited_message"),
      api.msg({ id: -100500, type: "channel", title: "Signals", username: "signals_ch" }, { message_id: 8, text: "Selling $NEAR, top is in" }, "channel_post"),
    );
    await tg.pollOnce();
    expect(tg.calls().map((c) => c.id)).toEqual(["tg--100500-8"]);
    expect(tg.calls()[0]).toMatchObject({ chatTitle: "Signals", direction: "sell", asset: "NEAR", from: {} });
    // Exactly 1500 is allowed; one more is not.
    api.queue.push(api.msg(group, { message_id: 9, from: person, text: `${buy} ${"x".repeat(1500 - buy.length - 1)}` }));
    await tg.pollOnce();
    expect(tg.calls().map((c) => c.id)).toContain("tg--100200-9");
  });

  it("with TELEGRAM_CHAT_IDS, only those chats; without, any group", async () => {
    const api = fakeBotApi();
    const only = telegramSource({ token: TOKEN, fetcher: api.fetcher, chatIds: ["-100300"] });
    api.queue.push(
      api.msg(group, { message_id: 1, from: person, text: "$SOL buying here" }),
      api.msg(privateGroup, { message_id: 2, from: person, text: "$SOL buying here" }),
    );
    await only.pollOnce();
    expect(only.calls().map((c) => c.id)).toEqual(["tg--100300-2"]);
    expect(only.calls()[0]!.url).toBeNull();
    const any = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    await any.pollOnce();
    expect(any.calls()).toHaveLength(2);
  });

  it("keeps the last 50", async () => {
    const api = fakeBotApi();
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    for (let i = 1; i <= 60; i++) api.queue.push(api.msg(group, { message_id: i, date: T0 + i, from: person, text: "$SOL buying here" }));
    await tg.pollOnce();
    expect(tg.calls()).toHaveLength(50);
    expect(tg.calls()[0]!.id).toBe("tg--100200-60");
  });

  it("shows plain text: control characters out, at most 600 characters", async () => {
    expect(tidyText("a\u0000b‮c\nd\te")).toBe("a b c d e");
    expect(tidyText("x".repeat(900))).toHaveLength(600);
    const api = fakeBotApi();
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    api.queue.push(api.msg(group, { message_id: 1, from: person, text: `$SOL buying\u0007 here\n${"y".repeat(700)}` }));
    await tg.pollOnce();
    const t = tg.calls()[0]!.text;
    expect(t.length).toBeLessThanOrEqual(600);
    expect(t).not.toMatch(/[\u0000-\u001f]/);
  });

  it("reports the groups it has read and the bot's name, and never anything else", async () => {
    const api = fakeBotApi();
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher });
    api.queue.push(
      api.msg(group, { message_id: 1, from: person, text: "$SOL buying here" }),
      api.msg(group, { message_id: 2, from: person, text: "hello" }),
      api.msg(privateGroup, { message_id: 3, from: person, text: "hello" }),
    );
    await tg.pollOnce();
    const s = await tg.status();
    expect(s).toEqual({
      configured: true,
      bot: "@keybots_bot",
      groups: [{ title: "Alpha Calls", messages: 2 }, { title: "Friends", messages: 1 }],
      lastMessageAt: new Date(T0 * 1000).toISOString(),
      error: null,
    });
    expect(api.requests.filter((r) => r.method === "getMe")).toHaveLength(1);
    await tg.status();
    expect(api.requests.filter((r) => r.method === "getMe")).toHaveLength(1); // cached
  });

  it("does nothing without a token", async () => {
    const api = fakeBotApi();
    for (const token of ["", "  ", "not a token", "12:short"]) {
      const tg = telegramSource({ token, fetcher: api.fetcher });
      tg.start();
      expect(tg.configured).toBe(false);
      expect(await tg.pollOnce()).toBe(0);
      expect(await tg.status()).toMatchObject({ configured: false, bot: null, groups: [] });
    }
    expect(api.requests).toHaveLength(0);
  });
});

describe("which messages read as a call", () => {
  it("keeps spot buys and sells; drops perps, contract addresses and chat", () => {
    expect(readAsCall("$SOL looks strong, buying here")).toEqual({ asset: "SOL", direction: "buy" });
    expect(readAsCall("Selling my $NEAR, top is in")).toEqual({ asset: "NEAR", direction: "sell" });
    for (const t of [
      "$ETH long 10x, send it",
      "shorting $BTC with leverage",
      "$SOL buying 0x1234567890abcdef1234567890abcdef12345678",
      "$BONK buying So11111111111111111111111111111111111111112",
      "good morning everyone",
      "anyone watching the game tonight?",
      "$SOL is it a buy or a sell?",
    ]) {
      expect(readAsCall(t), t).toBeNull();
    }
  });
});

describe("the token", () => {
  it("is read from the environment or keys/telegram.token, and a bad one is ignored", () => {
    const dir = mkdtempSync(join(tmpdir(), "tg-keys-"));
    expect(loadConfig({ AIRKEY_KEYS_DIR: dir }).telegram).toEqual({ token: "", chatIds: [] });
    writeFileSync(join(dir, "telegram.token"), `${TOKEN}\n`);
    expect(loadConfig({ AIRKEY_KEYS_DIR: dir, TELEGRAM_CHAT_IDS: "-100200, -100300," }).telegram).toEqual({ token: TOKEN, chatIds: ["-100200", "-100300"] });
    expect(loadConfig({ AIRKEY_KEYS_DIR: dir, TELEGRAM_BOT_TOKEN: "x/../y" }).telegram.token).toBe("");
    expect(cleanToken(` ${TOKEN} `)).toBe(TOKEN);
  });

  it("never appears in a failure, in the status, in a response or in the log", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const api = fakeBotApi({ fail: "fetch failed" });
    const tg = telegramSource({ token: TOKEN, fetcher: api.fetcher, retryMs: 20 });
    await expect(tg.pollOnce()).rejects.toThrow(/fetch failed/);
    await tg.pollOnce().catch((e) => expect(String(e.message)).not.toContain(TOKEN));
    tg.start();
    await new Promise((r) => setTimeout(r, 80));
    tg.stop();
    const app = buildApp({ cfg: { ...loadConfig({ AIRKEY_OWNER: "x.testnet" }), nearAi: { apiKey: "", model: "m", base: "b" }, openAi: { apiKey: "", model: "m", base: "b" } }, chain: {} as never, receipts: {} as never, kall: fakeKall({}), telegram: tg });
    const status = await app.inject("/v1/telegram/status");
    const everything = JSON.stringify([status.json(), (await app.inject("/v1/kol/feed")).json(), errors.mock.calls]);
    expect(status.json().error).toMatch(/fetch failed/);
    expect(everything).not.toContain(TOKEN);
    expect(everything).not.toContain("AAFakeToken");
    expect(errors).toHaveBeenCalled();
  });
});

describe("a restart", () => {
  it("keeps the calls from telegram-calls.jsonl, once each, newest 50", async () => {
    const dir = mkdtempSync(join(tmpdir(), "tg-data-"));
    const api = fakeBotApi();
    const first = telegramSource({ token: TOKEN, fetcher: api.fetcher, dataDir: dir });
    api.queue.push(
      api.msg(group, { message_id: 1, from: person, text: "$SOL buying here" }),
      api.msg(privateGroup, { message_id: 2, date: T0 + 5, from: person, text: "Selling my $NEAR, top is in" }),
      api.msg(group, { message_id: 3, from: person, text: "just chatting" }),
    );
    await first.pollOnce();
    expect(first.calls()).toHaveLength(2);
    // Only calls are written, one line each, and never the token.
    const raw = readFileSync(join(dir, "telegram-calls.jsonl"), "utf8");
    expect(raw.trim().split("\n")).toHaveLength(2);
    expect(raw).not.toContain(TOKEN);
    expect(raw).not.toContain("just chatting");

    // A new process with a fresh offset gets the same updates again from Telegram: no duplicates.
    const second = telegramSource({ token: TOKEN, fetcher: api.fetcher, dataDir: dir });
    expect(second.calls().map((c) => c.id)).toEqual(["tg--100300-2", "tg--100200-1"]);
    expect(second.find("tg--100200-1")).toMatchObject({ asset: "SOL", url: "https://t.me/alphacalls/1" });
    await second.pollOnce();
    expect(second.calls()).toHaveLength(2);
    // A hand-edited or damaged line is skipped, not fatal.
    writeFileSync(join(dir, "telegram-calls.jsonl"), `${raw}not json\n{"id":"x"}\n`);
    expect(telegramSource({ token: TOKEN, fetcher: api.fetcher, dataDir: dir }).calls()).toHaveLength(2);
    expect((await second.status()).groups.map((g) => g.title).sort()).toEqual(["Alpha Calls", "Friends"]);
  });
});
