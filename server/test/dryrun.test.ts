import { describe, expect, it } from "vitest";
import { loadConfig } from "../src/config.js";
import { dryRun, format, near } from "../src/dryrun.js";
import type { LeashState } from "../src/near.js";

const cfg = loadConfig({ AIRKEY_OWNER: "airkey-harshal.testnet" });
const N = (n: number) => (BigInt(Math.round(n * 1000)) * 10n ** 21n).toString();
const today = Math.floor(Date.now() / 86_400_000);
const agent = (tier: "trusted" | "untrusted", per: number, daily: number, spent = 0) => ({
  tier,
  per_payment_cap: N(per),
  daily_cap: N(daily),
  spent_today: N(spent),
  day: today,
});

/** The leash's view calls, faked: the same shape `get_state`'s pieces have on chain. */
function leash(over: Partial<LeashState> = {}): LeashState {
  return {
    owner: "airkey-harshal.testnet",
    leash: "leash.airkey-harshal.testnet",
    paused: false,
    available: N(1.2),
    agents: [
      { account: "pay.airkey-harshal.testnet", agent: agent("trusted", 0.5, 1) },
      { account: "inbox.airkey-harshal.testnet", agent: agent("untrusted", 0.5, 1) },
      { account: "trader.airkey-harshal.testnet", agent: agent("trusted", 1, 2, 0.295) },
    ],
    allowlist: ["friend.airkey-harshal.testnet"],
    blocklist: [{ account: "drain.airkey-harshal.testnet", reason: "reported by inbox: asked for an urgent payment" }],
    pending: [],
    ...over,
  };
}

const deps = (state = leash(), extra: Record<string, unknown> = {}) => ({
  cfg,
  chain: { state: async () => state, facts: async () => ({ exists: true, isContract: false, createdAtNs: null }) },
  rhea: {
    network: { exchange: "ref-finance-101.testnet" } as never,
    route: (s: string) => (s === "USDC" ? ({ symbol: "USDC", pool: 1103, decimals: 6, token: "usdc.testnet" } as never) : undefined),
    quote: async () => "630200",
  },
  ...extra,
});

const verdict = (r: Awaited<ReturnType<typeof dryRun>>) => r.lines.find(([k]) => k === "Verdict")![1];
const why = (r: Awaited<ReturnType<typeof dryRun>>) => r.lines.find(([k]) => k === "Why")?.[1];

describe("dry run", () => {
  it("pays an allowed friend from what you type", async () => {
    const r = await dryRun(deps(), "pay harshal 0.2 for dinner");
    expect(r.outcome).toBe("pay");
    expect(verdict(r)).toBe("Would pay 0.2 NEAR to friend.airkey-harshal.testnet");
    expect(why(r)).toBe("within 0.5 NEAR per payment and 1.0 NEAR today (0.0 spent)");
    const out = format(r);
    expect(out).toContain("Agent         Pay Agent (pay.airkey-harshal.testnet), trusted");
    expect(out).toContain("Leash         leash.airkey-harshal.testnet: 1.20 NEAR, Stop everything off");
    expect(out).toMatch(/Dry run: nothing was sent/);
  });

  it("blocks the blocked list before any cap, as the contract does", async () => {
    const r = await dryRun(deps(), "pay drain 5", { pasted: true });
    expect(r.outcome).toBe("blocked");
    expect(verdict(r)).toBe("Would be blocked: drain.airkey-harshal.testnet is on the blocked list (checked on chain by the contract)");
    expect(r.lines.find(([k]) => k === "Agent")![1]).toMatch(/^Inbox Agent .*untrusted$/);
  });

  it("holds a pasted payment to a new account for the owner", async () => {
    const r = await dryRun(deps(), "pay vendor 0.4 for the logo", { pasted: true });
    expect(r.outcome).toBe("wait");
    expect(verdict(r)).toBe("Would wait for the owner's Face ID: vendor.airkey-harshal.testnet is new and the Inbox Agent can only pay allowed accounts");
  });

  it("asks the owner for a typed payment to someone never paid", async () => {
    const r = await dryRun(deps(), "pay vendor 0.1");
    expect(r.outcome).toBe("wait");
    expect(verdict(r)).toMatch(/Face ID: the owner has never paid this account/);
  });

  it("stops everything when the kill switch is on", async () => {
    const r = await dryRun(deps(leash({ paused: true })), "pay harshal 0.2");
    expect(verdict(r)).toBe("Would be blocked: Stop everything is on");
    expect(r.lines.find(([k]) => k === "Leash")![1]).toMatch(/Stop everything on$/);
  });

  it("holds to the per-payment and daily limits", async () => {
    expect(verdict(await dryRun(deps(), "pay harshal 0.6"))).toBe("Would be blocked: 0.6 NEAR is over the 0.5 NEAR per payment limit");
    const spent = leash({ agents: [{ account: "pay.airkey-harshal.testnet", agent: agent("trusted", 0.5, 1, 0.9) }] });
    const r = await dryRun(deps(spent), "pay harshal 0.2");
    expect(verdict(r)).toBe("Would be blocked: over today's 1.0 NEAR limit");
    expect(why(r)).toBe("0.9 NEAR already spent today, 0.1 NEAR left");
  });

  it("counts yesterday's spend as zero, as the contract does", async () => {
    const old = leash({ agents: [{ account: "pay.airkey-harshal.testnet", agent: { ...agent("trusted", 0.5, 1, 0.9), day: today - 1 } }] });
    expect((await dryRun(deps(old), "pay harshal 0.2")).outcome).toBe("pay");
  });

  it("blocks when Spend Limits doesn't hold enough", async () => {
    expect(verdict(await dryRun(deps(leash({ available: N(0.1) })), "pay harshal 0.2"))).toBe("Would be blocked: Spend Limits doesn't hold enough NEAR");
  });

  it("checks a swap against the Trading Agent's caps and quotes it", async () => {
    const intents = {
      pick: async (s: string) => ({ asked: s, verified: true, token: { symbol: s } as never, alsoOn: [], reason: "" }),
      quote: async () => ({ dry: true, amountOutFormatted: "1.0031", amountOutUsd: "1.00" }) as never,
    };
    const r = await dryRun(deps(leash(), { intents }), "swap 0.3 near to usdc");
    expect(r.outcome).toBe("swap");
    expect(verdict(r)).toBe("Would swap 0.3 NEAR to USDC");
    expect(why(r)).toBe("within 1.0 NEAR per trade and 2.0 NEAR today (0.295 spent)");
    expect(r.lines).toContainEqual(["Rhea", "about 0.6302 USDC from pool 1103 (where Spend Limits swaps on testnet)"]);
    expect(r.lines).toContainEqual(["NEAR Intents", "about 1.003 USDC (~$1.00), live mainnet quote"]);
  });

  it("never trades from a pasted message", async () => {
    const r = await dryRun(deps(), "swap 0.3 near to usdc", { pasted: true });
    expect(verdict(r)).toBe("Would be blocked: trades only run from what you type, never from a copied message");
  });

  it("says when it can't read the words, and never uses rule ids", async () => {
    const r = await dryRun(deps(), "hello there");
    expect(r.outcome).toBe("unreadable");
    for (const t of ["pay harshal 0.2", "pay drain 5", "pay harshal 0.6", "hello"]) {
      expect(format(await dryRun(deps(), t))).not.toMatch(/\bR\d\b/);
    }
  });

  it("writes NEAR plainly", () => {
    expect(near(N(1.2049), 2, 2)).toBe("1.20");
    expect(near(N(0.5))).toBe("0.5");
    expect(near(0n)).toBe("0.0");
    expect(near(N(0.295))).toBe("0.295");
  });
});
