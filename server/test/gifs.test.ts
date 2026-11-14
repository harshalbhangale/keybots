import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { gifClient, parseKlipy, type GifEnv } from "../src/gifs.js";

// A made-up key: the test only checks where it goes.
const FAKE_KEY = "fake-klipy-key-for-tests";
const cfg = loadConfig({ AIRKEY_OWNER: "x.testnet" });

function klipyItem(slug: string) {
  const v = (size: string) => ({
    gif: { url: `https://static.klipy.test/${slug}/${size}.gif`, width: size === "xs" ? 90 : 220, height: size === "xs" ? 60 : 146 },
    webp: { url: `https://static.klipy.test/${slug}/${size}.webp`, width: 90, height: 60 },
  });
  return { id: 1, slug, title: `${slug} gif`, type: "gif", file: { hd: v("hd"), md: v("md"), sm: v("sm"), xs: v("xs") } };
}

/** A fake KLIPY: records every URL asked for, answers with two GIFs and an ad. */
function fakeKlipy(status = 200) {
  const urls: string[] = [];
  const impl = (async (u: string | URL) => {
    urls.push(String(u));
    if (status !== 200) return new Response("{}", { status });
    const body = { result: true, data: { data: [klipyItem("cat-wave"), { type: "ad", content: "<ad/>" }, klipyItem("dog-yes")], current_page: 1, has_next: true } };
    return new Response(JSON.stringify(body));
  }) as unknown as typeof fetch;
  return { impl, urls };
}

function appWith(env: GifEnv, fetchImpl: typeof fetch) {
  return buildApp({ cfg, chain: {} as never, receipts: {} as never, gifs: gifClient(env, fetchImpl) });
}

describe("GET /v1/gifs", () => {
  it("gives trending with the board's shape when q is empty", async () => {
    const k = fakeKlipy();
    const res = await appWith({ KLIPY_APP_KEY: FAKE_KEY, KLIPY_BASE_URL: "https://klipy.test/api/v1" }, k.impl).inject({ url: "/v1/gifs" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.attribution).toBe("Powered by KLIPY");
    expect(body.next).toBe(2);
    expect(body.items).toHaveLength(2); // the ad is skipped
    expect(body.items[0]).toEqual({
      id: "cat-wave",
      title: "cat-wave gif",
      preview: "https://static.klipy.test/cat-wave/xs.gif",
      pw: 90,
      ph: 60,
      url: "https://static.klipy.test/cat-wave/md.gif",
      w: 220,
      h: 146,
    });
    expect(k.urls).toHaveLength(1);
    const asked = new URL(k.urls[0]);
    expect(asked.pathname).toBe(`/api/v1/${FAKE_KEY}/gifs/trending`);
    expect(asked.searchParams.get("q")).toBeNull();
  });

  it("searches when q is given, and pages", async () => {
    const k = fakeKlipy();
    const res = await appWith({ KLIPY_APP_KEY: FAKE_KEY, KLIPY_BASE_URL: "https://klipy.test/api/v1/" }, k.impl).inject({ url: "/v1/gifs?q=thank%20you&page=3" });
    expect(res.statusCode).toBe(200);
    const asked = new URL(k.urls[0]);
    expect(asked.pathname).toBe(`/api/v1/${FAKE_KEY}/gifs/search`);
    expect(asked.searchParams.get("q")).toBe("thank you");
    expect(asked.searchParams.get("page")).toBe("3");
  });

  it("falls back to KLIPY_API_KEY and KLIPY's own address", async () => {
    const k = fakeKlipy();
    await appWith({ KLIPY_API_KEY: FAKE_KEY }, k.impl).inject({ url: "/v1/gifs" });
    expect(k.urls[0].startsWith(`https://api.klipy.com/api/v1/${FAKE_KEY}/gifs/trending?`)).toBe(true);
  });

  it("says 503 when no key is set, and asks KLIPY nothing", async () => {
    const k = fakeKlipy();
    const res = await appWith({}, k.impl).inject({ url: "/v1/gifs?q=haha" });
    expect(res.statusCode).toBe(503);
    expect(res.json()).toEqual({ error: "GIFs aren't set up on this server" });
    expect(k.urls).toHaveLength(0);
  });

  it("sends the key only to KLIPY, never back to the phone", async () => {
    const k = fakeKlipy();
    const app = appWith({ KLIPY_APP_KEY: FAKE_KEY }, k.impl);
    const ok = await app.inject({ url: "/v1/gifs?q=wow" });
    expect(ok.body).not.toContain(FAKE_KEY);
    expect(JSON.stringify(ok.headers)).not.toContain(FAKE_KEY);
    expect(k.urls.every((u) => u.startsWith("https://api.klipy.com/"))).toBe(true);
    // A failing KLIPY doesn't leak it either.
    const down = fakeKlipy(500);
    const bad = await appWith({ KLIPY_APP_KEY: FAKE_KEY }, down.impl).inject({ url: "/v1/gifs" });
    expect(bad.statusCode).toBe(502);
    expect(bad.body).not.toContain(FAKE_KEY);
    const thrown = (async () => {
      throw new Error(`fetch failed for https://api.klipy.com/api/v1/${FAKE_KEY}/gifs/trending`);
    }) as unknown as typeof fetch;
    const net = await appWith({ KLIPY_APP_KEY: FAKE_KEY }, thrown).inject({ url: "/v1/gifs" });
    expect(net.statusCode).toBe(502);
    expect(net.body).not.toContain(FAKE_KEY);
  });

  it("keeps a page for 60 seconds", async () => {
    const k = fakeKlipy();
    let t = 1_000_000;
    const client = gifClient({ KLIPY_APP_KEY: FAKE_KEY }, k.impl, () => t);
    await client.page("sad", 1);
    await client.page("sad", 1);
    expect(k.urls).toHaveLength(1);
    await client.page("sad", 2);
    expect(k.urls).toHaveLength(2);
    t += 61_000;
    await client.page("sad", 1);
    expect(k.urls).toHaveLength(3);
  });

  it("needs the same token as every other route", async () => {
    const k = fakeKlipy();
    const app = buildApp({ cfg: { ...cfg, apiToken: "t0k" }, chain: {} as never, receipts: {} as never, gifs: gifClient({ KLIPY_APP_KEY: FAKE_KEY }, k.impl) });
    expect((await app.inject({ url: "/v1/gifs" })).statusCode).toBe(401);
    expect((await app.inject({ url: "/v1/gifs", headers: { authorization: "Bearer t0k" } })).statusCode).toBe(200);
  });
});

describe("parseKlipy", () => {
  it("drops items without a usable https GIF, and has no next on the last page", () => {
    const page = parseKlipy({ result: true, data: { data: [{ slug: "x", file: { md: { gif: { url: "http://insecure/x.gif" } } } }], current_page: 4, has_next: false } });
    expect(page.items).toEqual([]);
    expect(page.next).toBeNull();
  });
});
