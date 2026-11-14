// A fake Telegram Bot API for the tests: no network.
export const TOKEN = "123456789:AAFakeTokenFakeTokenFakeToken_abc";
export const T0 = 1_800_000_000;

type Update = Record<string, unknown>;

/** A fake Bot API. getUpdates hands out what's queued with update_id >= the offset it was asked for, as Telegram does. */
export function fakeBotApi(opts: { fail?: string } = {}) {
  const queue: Update[] = [];
  const requests: { method: string; body: Record<string, unknown>; url: string }[] = [];
  const fetcher = (async (url: string, init?: RequestInit) => {
    const method = String(url).split("/").pop()!;
    const body = JSON.parse(String(init?.body ?? "{}"));
    requests.push({ method, body, url: String(url) });
    if (opts.fail) throw new Error(`${opts.fail} (${url})`);
    const reply = (result: unknown) => new Response(JSON.stringify({ ok: true, result }), { status: 200 });
    if (method === "getMe") return reply({ id: 1, is_bot: true, username: "keybots_bot" });
    if (method === "getUpdates") return reply(queue.filter((u) => (u.update_id as number) >= (body.offset as number)));
    return new Response(JSON.stringify({ ok: false, description: "nope" }), { status: 404 });
  }) as unknown as typeof fetch;
  let id = 100;
  const msg = (chat: Record<string, unknown>, m: Record<string, unknown>, key = "message"): Update => ({ update_id: id++, [key]: { chat, date: T0, ...m } });
  return { queue, requests, fetcher, msg };
}

export const group = { id: -100200, type: "supergroup", title: "Alpha Calls", username: "alphacalls" };
export const privateGroup = { id: -100300, type: "group", title: "Friends" };
export const person = { id: 7, is_bot: false, username: "sol_sam", first_name: "Sam" };

