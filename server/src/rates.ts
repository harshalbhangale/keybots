// Fiat exchange rates for "100 usd to inr" in the keyboard. One keyless call
// to open.er-api.com, cached for an hour; every rate is per 1 USD.

export interface Rates {
  date: string;
  perUsd: Record<string, number>;
}

export function ratesClient(opts: { fetchImpl?: typeof fetch; url?: string } = {}) {
  const f = opts.fetchImpl ?? fetch;
  const url = opts.url ?? "https://open.er-api.com/v6/latest/USD";
  let cache: { at: number; rates: Rates } | null = null;

  async function rates(): Promise<Rates> {
    if (cache && Date.now() - cache.at < 60 * 60_000) return cache.rates;
    const r = await f(url, { signal: AbortSignal.timeout(10_000) });
    const j = (await r.json()) as { result?: string; rates?: Record<string, number>; time_last_update_utc?: string };
    if (!r.ok || j.result !== "success" || !j.rates) throw new Error(`The rates service answered ${r.status}`);
    cache = { at: Date.now(), rates: { date: j.time_last_update_utc ?? new Date().toUTCString(), perUsd: j.rates } };
    return cache.rates;
  }

  /** amount of `from` in `to`, or null if either currency is unknown. */
  async function convert(amount: number, from: string, to: string): Promise<{ value: number; rate: number; date: string } | null> {
    const { perUsd, date } = await rates();
    const a = perUsd[from.toUpperCase()];
    const b = perUsd[to.toUpperCase()];
    if (!a || !b || !Number.isFinite(amount)) return null;
    const rate = b / a;
    return { value: amount * rate, rate, date };
  }

  return { rates, convert };
}

export type RatesClient = ReturnType<typeof ratesClient>;
