import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { AttestationCache, NRAS, PHALA_VERIFY, quoteFields, verifyAttestation, type AttestationResult } from "../src/attest.js";

// One real report from cloud-api.near.ai for Qwen/Qwen3-VL-30B-A3B-Instruct, as it came back.
const REPORT = readFileSync(new URL("./fixtures/near-ai-attestation.json", import.meta.url), "utf8");
const real = () => JSON.parse(REPORT);
const NONCE: string = real().model_attestations[0].request_nonce;
const MODEL_SIGNER: string = real().model_attestations[0].signing_address;
const GATEWAY_SIGNER: string = real().gateway_attestation.signing_address;
const cfg = { apiKey: "test", model: "Qwen/Qwen3-VL-30B-A3B-Instruct", base: "https://cloud-api.near.ai/v1" };

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const jwt = (claims: object) => `e30.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.sig`;

interface Fake {
  report?: () => Response;
  phala?: (quoteHex: string) => Response;
  nras?: (payload: { nonce: string }) => Response;
}

/** The report endpoint, Phala's verifier and NRAS, answering like the real ones did. */
function fakeFetch(f: Fake = {}): typeof fetch {
  return (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/attestation/report")) return f.report ? f.report() : json(real());
    if (url === PHALA_VERIFY) {
      const { hex } = JSON.parse(String(init?.body));
      if (f.phala) return f.phala(hex);
      return json({ success: true, quote: { verified: true, body: { reportdata: "0x" + quoteFields(hex)!.reportData.toString("hex") } } });
    }
    if (url === NRAS) {
      const payload = JSON.parse(String(init?.body));
      if (f.nras) return f.nras(payload);
      return json([["JWT", jwt({ "x-nvidia-overall-att-result": true, eat_nonce: payload.nonce })], {}]);
    }
    throw new Error(`unexpected ${url}`);
  }) as typeof fetch;
}

describe("verifyAttestation on a recorded real report", () => {
  it("reads the report data from the TDX quote where the API says it is", () => {
    const gw = real().gateway_attestation;
    expect(quoteFields(gw.intel_quote)!.reportData.toString("hex")).toBe(gw.report_data);
  });

  it("all good: verified, every check passed", async () => {
    const r = await verifyAttestation(cfg, fakeFetch(), NONCE);
    expect(r.status).toBe("verified");
    expect(r.checks).toEqual({ nonce: true, reportData: true, signerMatch: null, tdxQuote: "verified", nvidia: "verified", composeHash: true });
    expect(r.signingAddress).toBe(MODEL_SIGNER.toLowerCase());
    expect(r.gatewaySigningAddress).toBe(GATEWAY_SIGNER.toLowerCase());
  });

  it("a different nonce fails, and NRAS is never asked about it", async () => {
    let asked = false;
    const r = await verifyAttestation(cfg, fakeFetch({ nras: () => ((asked = true), json([])) }), "ab".repeat(32));
    expect(r.status).toBe("failed");
    expect(r.checks.nonce).toBe(false);
    expect(r.checks.nvidia).toBe("failed");
    expect(asked).toBe(false);
  });

  it("a signing address the quote does not bind fails", async () => {
    const body = real();
    body.model_attestations[0].signing_address = "0x" + "11".repeat(20);
    const r = await verifyAttestation(cfg, fakeFetch({ report: () => json(body) }), NONCE);
    expect(r.status).toBe("failed");
    expect(r.checks.reportData).toBe(false);
  });

  it("a changed app_compose fails the compose hash", async () => {
    const body = real();
    body.model_attestations[0].info.tcb_info.app_compose += " ";
    const r = await verifyAttestation(cfg, fakeFetch({ report: () => json(body) }), NONCE);
    expect(r.status).toBe("failed");
    expect(r.checks.composeHash).toBe(false);
  });

  it("the quote verifier down: partial, never verified", async () => {
    const r = await verifyAttestation(cfg, fakeFetch({ phala: () => json({ error: "down" }, 503) }), NONCE);
    expect(r.status).toBe("partial");
    expect(r.checks.tdxQuote).toBe("unavailable");
    expect(r.checks.nvidia).toBe("verified");
  });

  it("the quote verifier says no: failed", async () => {
    const r = await verifyAttestation(cfg, fakeFetch({ phala: () => json({ success: true, quote: { verified: false } }) }), NONCE);
    expect(r.status).toBe("failed");
    expect(r.checks.tdxQuote).toBe("failed");
  });

  it("NRAS down: partial; NRAS says false: failed", async () => {
    const down = await verifyAttestation(cfg, fakeFetch({ nras: () => json({}, 502) }), NONCE);
    expect(down.status).toBe("partial");
    expect(down.checks.nvidia).toBe("unavailable");
    const no = await verifyAttestation(cfg, fakeFetch({ nras: (p) => json([["JWT", jwt({ "x-nvidia-overall-att-result": false, eat_nonce: p.nonce })]]) }), NONCE);
    expect(no.status).toBe("failed");
    expect(no.checks.nvidia).toBe("failed");
  });

  it("no report: unavailable", async () => {
    const r = await verifyAttestation(cfg, fakeFetch({ report: () => json({ error: "no" }, 500) }), NONCE);
    expect(r.status).toBe("unavailable");
  });
});

describe("AttestationCache.evidenceFor", () => {
  const cached = async (): Promise<AttestationCache> => {
    const c = new AttestationCache();
    c.set(await verifyAttestation(cfg, fakeFetch(), NONCE));
    return c;
  };
  const sig = (signingAddress: string, kind = "provider_tee") => ({ status: "verified", kind, signingAddress });

  it("nothing checked yet: not checked", () => {
    expect(new AttestationCache().evidenceFor(cfg.model, sig(MODEL_SIGNER))).toEqual({ attestation: "not checked" });
  });

  it("an answer signed by the attested enclave: verified", async () => {
    const e = (await cached()).evidenceFor(cfg.model, sig(MODEL_SIGNER.toUpperCase().replace("0X", "0x")));
    expect(e.attestation).toBe("verified");
    expect(e.attestationChecks?.signerMatch).toBe(true);
  });

  it("a gateway signature is matched with the gateway's address", async () => {
    expect((await cached()).evidenceFor(cfg.model, sig(GATEWAY_SIGNER, "gateway")).attestation).toBe("verified");
  });

  it("an answer signed by someone else: failed", async () => {
    const e = (await cached()).evidenceFor(cfg.model, sig("0x" + "22".repeat(20)));
    expect(e.attestation).toBe("failed");
    expect(e.attestationChecks?.signerMatch).toBe(false);
  });

  it("an answer whose signature could not be checked: partial", async () => {
    const e = (await cached()).evidenceFor(cfg.model, { status: "unavailable" });
    expect(e.attestation).toBe("partial");
    expect(e.attestationChecks?.signerMatch).toBeNull();
  });

  it("an unavailable or old check says not checked", async () => {
    const c = new AttestationCache();
    c.set({ status: "unavailable", checkedAt: new Date().toISOString(), model: cfg.model } as AttestationResult);
    expect(c.evidenceFor(cfg.model, sig(MODEL_SIGNER)).attestation).toBe("not checked");
    const old = new AttestationCache(10 * 60_000, () => Date.now() + 60 * 60_000);
    old.set(await verifyAttestation(cfg, fakeFetch(), NONCE));
    expect(old.evidenceFor(cfg.model, sig(MODEL_SIGNER)).attestation).toBe("not checked");
  });

  it("refreshes once at a time, and not while fresh", async () => {
    let reports = 0;
    const f = fakeFetch({ report: () => (reports++, json(real())) });
    const c = new AttestationCache();
    const a = c.refreshIfStale(cfg, f);
    expect(c.refreshIfStale(cfg, f)).toBe(a);
    await a;
    expect(c.refreshIfStale(cfg, f)).toBeUndefined();
    expect(reports).toBe(1);
  });
});
