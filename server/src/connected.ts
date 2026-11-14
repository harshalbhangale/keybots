import { attestations } from "./attest.js";
import type { Deps } from "./app.js";
import type { KallClient } from "./kall.js";

/**
 * What Keybots is connected to, checked live: each service gets one small
 * real call (a quote, a token list, a feed read) with a short timeout. Never
 * sends money, never shows a key or a message.
 */
export type ServiceStatus = "live" | "down" | "off";

export interface Service {
  id: "spend-limits" | "rhea" | "near-intents" | "near-ai" | "kall" | "telegram";
  name: string;
  /** What Keybots uses it for, in one line. */
  role: string;
  status: ServiceStatus;
  /** What the check saw, in plain words. */
  detail: string;
}

const TIMEOUT_MS = 4000;

async function probe(run: () => Promise<string>): Promise<{ status: ServiceStatus; detail: string }> {
  let timer: NodeJS.Timeout | undefined;
  try {
    const detail = await Promise.race([
      run(),
      new Promise<never>((_, no) => {
        timer = setTimeout(() => no(new Error("no answer in 4 s")), TIMEOUT_MS);
      }),
    ]);
    return { status: "live", detail };
  } catch (e) {
    return { status: "down", detail: String((e as Error).message ?? e).slice(0, 120) };
  } finally {
    clearTimeout(timer);
  }
}

const off = (detail: string) => ({ status: "off" as const, detail });

export async function connected(deps: Deps, kallApi: KallClient | undefined = deps.kall): Promise<{ checkedAt: string; network: string; services: Service[] }> {
  const { cfg } = deps;
  const usdc = deps.rhea?.route("USDC");
  const [limits, rhea, intents, kall, telegram] = await Promise.all([
    probe(async () => {
      const s = await deps.chain.state();
      return s.paused ? `${cfg.leash}: everything is stopped` : `${cfg.leash}: ${Object.keys(cfg.agents).length} agents, running`;
    }),
    deps.rhea?.network && usdc
      ? probe(async () => {
          const out = await deps.rhea!.quote(usdc, (10n ** 24n).toString());
          return `1 NEAR → ${(Number(out) / 10 ** usdc.decimals).toFixed(2)} ${usdc.symbol} (pool ${usdc.pool})`;
        })
      : Promise.resolve(off("Not set up on this server")),
    deps.intents
      ? probe(async () => `${(await deps.intents!.tokens()).length} tokens listed`)
      : Promise.resolve(off("Not set up on this server")),
    kallApi
      ? probe(async () => {
          const f = await kallApi.feed();
          return `${f.callers.length} callers, ${f.calls.length} calls`;
        })
      : Promise.resolve(off("Not set up on this server")),
    deps.telegram?.configured
      ? probe(async () => {
          const t = await deps.telegram!.status();
          if (t.error) throw new Error(t.error);
          const groups = t.groups.length;
          return `@${(t.bot ?? "bot").replace(/^@/, "")}${groups ? ` in ${groups} group${groups === 1 ? "" : "s"}` : ", waiting to be added to a group"}`;
        })
      : Promise.resolve(off("No bot token on this server")),
  ]);
  const att = cfg.nearAi.apiKey ? attestations.get(cfg.nearAi.model) : undefined;
  const ai = !cfg.nearAi.apiKey
    ? off("No NEAR AI key on this server")
    : !att
      ? { status: "down" as const, detail: "Hardware attestation not checked yet" }
      : att.status === "verified" || att.status === "partial"
        ? { status: "live" as const, detail: `${att.model}, attestation ${att.status}` }
        : { status: "down" as const, detail: `Attestation ${att.status}` };

  return {
    checkedAt: new Date().toISOString(),
    network: cfg.network,
    services: [
      { id: "spend-limits", name: "Spend Limits", role: "The NEAR contract that holds the money and decides every payment and swap", ...limits },
      { id: "rhea", name: "Rhea", role: "Where the Trading Agent's swaps run", ...rhea },
      { id: "near-intents", name: "NEAR Intents", role: "Checks a coin in a post is a real token, and its price", ...intents },
      { id: "near-ai", name: "NEAR AI Cloud", role: "The private AI behind hold space. Never sees money", ...ai },
      { id: "kall", name: "X, via Kall", role: "Trade calls from people on X", ...kall },
      { id: "telegram", name: "Telegram", role: "Trade calls from your Telegram group", ...telegram },
    ],
  };
}
