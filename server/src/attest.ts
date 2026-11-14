// Hardware attestation for NEAR AI Cloud, checked the way
// docs.near.ai/cloud/verification/reference/quote-nonce-signer describes:
//
// 1. A fresh 32-byte nonce goes with the report request.
// 2. Nonce: the report echoes it, and the last 32 bytes of each TDX quote's
//    report data are that nonce.
// 3. Report data: the first 32 bytes of each quote's report data are the
//    signing address, zero padded, so the key that signs answers lives in
//    that enclave.
// 4. TDX quote: Phala's public verifier checks the Intel signature chain and
//    collateral; we require it to say verified, to read the same report data
//    we read, and the TD not to be in debug mode.
// 5. NVIDIA: each model's GPU evidence goes to NVIDIA NRAS, which must answer
//    with an overall result of true for our nonce.
// 6. Compose hash: sha256 of app_compose matches tcb_info.compose_hash and
//    the quote's MRCONFIGID, and replaying the event log gives the quote's
//    RTMR3.
// 7. Signer: each answer's recovered signer is compared with the attested
//    address (per answer, in evidenceFor).
//
// Attestation is per enclave, not per answer: one result is kept per model
// for ten minutes and refreshed in the background.
import { createHash, randomBytes } from "node:crypto";

export type Verdict = "verified" | "failed" | "unavailable";

export interface AttestationChecks {
  nonce: boolean;
  reportData: boolean;
  signerMatch: boolean | null;
  tdxQuote: Verdict;
  nvidia: Verdict;
  composeHash: boolean | null;
}

export interface AttestationResult {
  status: "verified" | "partial" | "failed" | "unavailable";
  checkedAt: string;
  model: string;
  /** The model enclave's signing address (provider_tee signatures). */
  signingAddress: string | null;
  /** The gateway's signing address (gateway signatures). */
  gatewaySigningAddress: string | null;
  checks: AttestationChecks;
  detail: string;
}

export interface AttestConfig {
  apiKey: string;
  model: string;
  base: string;
}

export const PHALA_VERIFY = "https://cloud-api.phala.network/api/v1/attestations/verify";
export const NRAS = "https://nras.attestation.nvidia.com/v3/attest/gpu";
const VERIFIER_MS = 10_000;

interface Report {
  signing_address?: string;
  signing_algo?: string;
  request_nonce?: string;
  intel_quote?: string;
  report_data?: string;
  event_log?: unknown;
  nvidia_payload?: string;
  info?: { tcb_info?: unknown; compose_hash?: string };
}

const hex = (s: string) => Buffer.from(s.replace(/^0x/i, ""), "hex");
const parse = <T>(v: unknown): T => (typeof v === "string" ? JSON.parse(v) : v) as T;
const sha = (alg: string, ...parts: (Buffer | string)[]) => {
  const h = createHash(alg);
  for (const p of parts) h.update(p);
  return h.digest();
};

/** The parts of a TDX v4 quote we read: 48-byte header, then the TD report body. */
export function quoteFields(quoteHex: string) {
  const q = hex(quoteHex);
  if (q.length < 632 || q.readUInt16LE(0) !== 4 || q.readUInt32LE(4) !== 0x81) return null;
  const body = 48;
  return {
    tdAttributes: q.subarray(body + 120, body + 128),
    mrConfigId: q.subarray(body + 184, body + 232),
    rtmr3: q.subarray(body + 472, body + 520),
    reportData: q.subarray(body + 520, body + 584),
  };
}

export function replayRtmr3(eventLog: unknown): Buffer {
  let rtmr3 = Buffer.alloc(48);
  for (const e of parse<{ imr: number; event_type: number; event: string; event_payload?: string; digest?: string }[]>(eventLog)) {
    if (e.imr !== 3) continue;
    const type = Buffer.alloc(4);
    type.writeUInt32LE(e.event_type);
    const digest = sha("sha384", type, ":", Buffer.from(e.event, "utf8"), ":", hex(e.event_payload ?? ""));
    if (e.digest && !hex(e.digest).equals(digest)) throw new Error(`event ${e.event} digest mismatch`);
    rtmr3 = sha("sha384", rtmr3, digest);
  }
  return rtmr3;
}

/** Phala's verifier on one quote: verified only when it says so and reads the report data we read. */
async function verifyQuote(quoteHex: string, reportData: Buffer, fetchImpl: typeof fetch): Promise<Verdict> {
  try {
    const r = await fetchImpl(PHALA_VERIFY, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ hex: quoteHex }),
      signal: AbortSignal.timeout(VERIFIER_MS),
    });
    if (!r.ok) return r.status >= 500 || r.status === 429 ? "unavailable" : "failed";
    const j = (await r.json()) as { success?: boolean; quote?: { verified?: boolean; body?: { reportdata?: string } } };
    const sameData = (j.quote?.body?.reportdata ?? "").replace(/^0x/i, "").toLowerCase() === reportData.toString("hex");
    return j.success === true && j.quote?.verified === true && sameData ? "verified" : "failed";
  } catch {
    return "unavailable";
  }
}

/** NVIDIA NRAS on one GPU payload: its JWT must say overall true, for our nonce. */
async function verifyGpu(payload: string | undefined, nonce: string, fetchImpl: typeof fetch): Promise<Verdict> {
  if (!payload) return "unavailable";
  let p: { nonce?: string };
  try {
    p = JSON.parse(payload);
  } catch {
    return "failed";
  }
  if (typeof p.nonce !== "string" || p.nonce.toLowerCase() !== nonce) return "failed";
  try {
    const r = await fetchImpl(NRAS, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: payload,
      signal: AbortSignal.timeout(VERIFIER_MS),
    });
    if (!r.ok) return r.status >= 500 || r.status === 429 ? "unavailable" : "failed";
    const j = (await r.json()) as unknown[];
    const first = Array.isArray(j) ? (j[0] as unknown[]) : null;
    if (!first || first[0] !== "JWT" || typeof first[1] !== "string") return "failed";
    const claims = JSON.parse(Buffer.from(first[1].split(".")[1] ?? "", "base64url").toString()) as Record<string, unknown>;
    const eatNonce = String(claims.eat_nonce ?? "").toLowerCase();
    return claims["x-nvidia-overall-att-result"] === true && (!eatNonce || eatNonce === nonce) ? "verified" : "failed";
  } catch {
    return "unavailable";
  }
}

const worst = (vs: Verdict[]): Verdict => (vs.includes("failed") ? "failed" : vs.includes("unavailable") || vs.length === 0 ? "unavailable" : "verified");

/** The local checks on one report, and its quote sent to the verifier. */
async function checkReport(r: Report, nonce: string, fetchImpl: typeof fetch, problems: string[], name: string) {
  const out = { nonce: false, reportData: false, tdxQuote: "failed" as Verdict, composeHash: null as boolean | null };
  out.nonce = (r.request_nonce ?? "").toLowerCase() === nonce;
  if (!out.nonce) problems.push(`${name}: the report did not echo our nonce`);
  const q = r.intel_quote ? quoteFields(r.intel_quote) : null;
  if (!q || !r.intel_quote) {
    problems.push(`${name}: no readable TDX quote`);
    return out;
  }
  if (q.reportData.subarray(32).toString("hex") !== nonce) {
    out.nonce = false;
    problems.push(`${name}: the quote does not carry our nonce`);
  }
  const id = hex(r.signing_address ?? "");
  const bound = r.signing_algo === "ecdsa" && id.length === 20 && q.reportData.subarray(0, 32).equals(Buffer.concat([id, Buffer.alloc(12)]));
  const fieldOk = !r.report_data || r.report_data.replace(/^0x/i, "").toLowerCase() === q.reportData.toString("hex");
  out.reportData = bound && fieldOk;
  if (!out.reportData) problems.push(`${name}: the quote does not bind the signing address`);

  // Compose hash and event log: the measured configuration is the one shown.
  try {
    const tcb = parse<{ app_compose?: string; compose_hash?: string; event_log?: unknown }>(r.info?.tcb_info);
    if (typeof tcb?.app_compose === "string") {
      const h = sha("sha256", Buffer.from(tcb.app_compose, "utf8"));
      const claimed = (tcb.compose_hash ?? r.info?.compose_hash ?? "").replace(/^0x/i, "").toLowerCase();
      const mrConfig = q.mrConfigId.equals(Buffer.concat([Buffer.from([1]), h, Buffer.alloc(15)]));
      const log = r.event_log ?? tcb.event_log;
      const rtmr3 = log ? replayRtmr3(log).equals(q.rtmr3) : false;
      out.composeHash = mrConfig && claimed === h.toString("hex") && rtmr3;
      if (!out.composeHash) problems.push(`${name}: the compose hash or event log does not match the quote`);
    }
  } catch {
    out.composeHash = false;
    problems.push(`${name}: the event log does not replay`);
  }

  if (q.tdAttributes[0] & 1) {
    problems.push(`${name}: the TD runs in debug mode`);
    return out;
  }
  out.tdxQuote = await verifyQuote(r.intel_quote, q.reportData, fetchImpl);
  if (out.tdxQuote !== "verified") problems.push(`${name}: TDX quote ${out.tdxQuote === "failed" ? "failed verification" : "verifier did not answer"}`);
  return out;
}

export function statusOf(c: AttestationChecks): "verified" | "partial" | "failed" {
  if (!c.nonce || !c.reportData || c.signerMatch === false || c.composeHash === false || c.tdxQuote === "failed" || c.nvidia === "failed") return "failed";
  if (c.tdxQuote === "unavailable" || c.nvidia === "unavailable" || c.composeHash === null) return "partial";
  return "verified";
}

const empty = (): AttestationChecks => ({ nonce: false, reportData: false, signerMatch: null, tdxQuote: "unavailable", nvidia: "unavailable", composeHash: null });

/** Fetch a fresh report for cfg.model and check it. Never throws. */
export async function verifyAttestation(cfg: AttestConfig, fetchImpl: typeof fetch = fetch, nonce = randomBytes(32).toString("hex")): Promise<AttestationResult> {
  const base = { checkedAt: new Date().toISOString(), model: cfg.model, signingAddress: null, gatewaySigningAddress: null };
  let body: { gateway_attestation?: Report; model_attestations?: Report[] };
  try {
    const q = new URLSearchParams({ model: cfg.model, provider: "near", signing_algo: "ecdsa", nonce, include_tls_fingerprint: "false" });
    const r = await fetchImpl(`${cfg.base}/attestation/report?${q}`, {
      headers: { authorization: `Bearer ${cfg.apiKey}`, accept: "application/json", "x-no-aliasing": "true" },
      signal: AbortSignal.timeout(20_000),
    });
    if (!r.ok) return { ...base, status: "unavailable", checks: empty(), detail: `NEAR AI Cloud answered ${r.status} for the attestation report` };
    body = (await r.json()) as typeof body;
  } catch (e) {
    return { ...base, status: "unavailable", checks: empty(), detail: `No attestation report: ${(e as Error).message}` };
  }
  const models = body.model_attestations ?? [];
  const gateway = body.gateway_attestation;
  if (models.length === 0) return { ...base, status: "unavailable", checks: empty(), detail: "The report had no model attestation" };

  const problems: string[] = [];
  const reports = [...models.map((m, i) => checkReport(m, nonce, fetchImpl, problems, `model ${i + 1}`)), ...(gateway ? [checkReport(gateway, nonce, fetchImpl, problems, "gateway")] : [])];
  const [results, gpus] = await Promise.all([Promise.all(reports), Promise.all(models.map((m) => verifyGpu(m.nvidia_payload, nonce, fetchImpl)))]);
  const nvidia = worst(gpus);
  if (nvidia !== "verified") problems.push(`GPU attestation ${nvidia === "failed" ? "failed" : "was not checked: NVIDIA did not answer or there was no GPU evidence"}`);
  const composes = results.map((r) => r.composeHash);
  const checks: AttestationChecks = {
    nonce: results.every((r) => r.nonce),
    reportData: results.every((r) => r.reportData),
    signerMatch: null,
    tdxQuote: worst(results.map((r) => r.tdxQuote)),
    nvidia,
    composeHash: composes.includes(false) ? false : composes.includes(null) ? null : true,
  };
  const status = statusOf(checks);
  return {
    ...base,
    signingAddress: models[0]?.signing_address?.toLowerCase() ?? null,
    gatewaySigningAddress: gateway?.signing_address?.toLowerCase() ?? null,
    status,
    checks,
    detail:
      status === "verified"
        ? "TDX quotes verified by Phala's verifier, GPU attestation verified by NVIDIA NRAS, nonce and signing address bound in the quotes, compose hash and event log match"
        : problems.join("; ") || "Not every check passed",
  };
}

/** What a receipt says about attestation, given the cached result and this answer's signer. */
export interface AttestationEvidence {
  attestation: "verified" | "partial" | "failed" | "not checked";
  attestationChecks?: AttestationChecks & { checkedAt: string };
}

/** One cached result per model, refreshed in the background, never awaited by an answer. */
export class AttestationCache {
  private results = new Map<string, AttestationResult>();
  private running = new Map<string, Promise<AttestationResult>>();
  private readonly ttlMs: number;
  private readonly now: () => number;
  constructor(ttlMs = 10 * 60_000, now = () => Date.now()) {
    this.ttlMs = ttlMs;
    this.now = now;
  }

  get(model: string): AttestationResult | undefined {
    const r = this.results.get(model);
    // Kept a little past its refresh time, never long past it.
    return r && this.now() - Date.parse(r.checkedAt) < this.ttlMs * 1.5 ? r : undefined;
  }

  set(r: AttestationResult): void {
    this.results.set(r.model, r);
  }

  /** Start a check when there is none or it is older than ten minutes. Returns at once. */
  refreshIfStale(cfg: AttestConfig, fetchImpl: typeof fetch = fetch): Promise<AttestationResult> | undefined {
    if (!cfg.apiKey) return undefined;
    const r = this.results.get(cfg.model);
    if (r && this.now() - Date.parse(r.checkedAt) < this.ttlMs) return undefined;
    const busy = this.running.get(cfg.model);
    if (busy) return busy;
    const p = verifyAttestation(cfg, fetchImpl)
      .then((res) => {
        this.set(res);
        return res;
      })
      .finally(() => this.running.delete(cfg.model));
    this.running.set(cfg.model, p);
    return p;
  }

  /** The receipt fields for one answer: the cached result plus whether this answer's signer is the attested one. */
  evidenceFor(model: string, sig: { status: string; kind?: string; signingAddress?: string }): AttestationEvidence {
    const r = this.get(model);
    if (!r || r.status === "unavailable") return { attestation: "not checked" };
    const attested = sig.kind === "gateway" ? r.gatewaySigningAddress : r.signingAddress;
    const signerMatch = sig.status === "verified" && sig.signingAddress && attested ? sig.signingAddress.toLowerCase() === attested : null;
    if (signerMatch !== null) {
      r.checks.signerMatch = signerMatch;
      r.status = statusOf(r.checks);
    }
    const checks = { ...r.checks, signerMatch, checkedAt: r.checkedAt };
    const status = statusOf(checks);
    // An answer whose signer we could not compare is only partly covered.
    return { attestation: status === "verified" && signerMatch !== true ? "partial" : status, attestationChecks: checks };
  }
}

/** The server's one cache. */
export const attestations = new AttestationCache();
