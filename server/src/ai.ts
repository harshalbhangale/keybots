// The AI reader: reads free-form text the rule parser couldn't, and records
// the evidence for each answer. NEAR AI Cloud (private inference, answers
// signed in a TEE) when NEAR_AI_API_KEY is set; otherwise OpenAI if a key is
// set, which reads just as well but isn't private and isn't signed.
//
// What we check, and what we don't (docs.near.ai/cloud/verification):
// - We keep the exact request and response bytes, fetch /v1/signature/<id>,
//   recover the ECDSA (EIP-191) signer, and check that the signed text is
//   "<model>:<sha256(request)>:<sha256(response)>" (provider_tee) or
//   "<sha256(request)>:<sha256(response)>" (gateway).
// - We do NOT yet verify the attestation report that ties that signing address
//   to TEE hardware. Receipts say so ("attestation": "not checked").
import { createHash } from "node:crypto";
import { recoverMessageAddress } from "viem";
import type { Action } from "./parse.js";

export interface AiConfig {
  provider: "near-ai-cloud" | "openai";
  apiKey: string;
  model: string;
  base: string;
}

export interface AiEvidence {
  provider: AiConfig["provider"];
  model: string;
  chatId: string | null;
  signature: {
    status: "verified" | "mismatch" | "unavailable";
    kind?: string;
    signingAddress?: string;
    algo: "ecdsa";
  };
  attestation: "not checked";
}

const SYSTEM = `You read one message and extract at most one money action from it.
Reply with JSON only, no prose:
{"kind":"pay","receiver":"<account or name>","amount_near":"<decimal>","memo":"<short or empty>"}
or {"kind":"swap","amount":"<decimal, in units of from>","from":"<SYMBOL>","to":"<SYMBOL>"}
or {"kind":"swap","amount_usd":"<decimal>","from":"<SYMBOL>","to":"<SYMBOL>"} when the amount is in dollars ("5 bucks of near")
or {"kind":"unknown"}
"buy X with Y" means from Y to X. "sell X" with no target means to USDC.
Copy the receiver exactly as written. Never invent an amount.`;

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

/** NEAR AI Cloud, the private reader. Kept for callers that only know it. */
export const readWithNearAi = (text: string, cfg: Omit<AiConfig, "provider">, fetchImpl: typeof fetch = fetch) =>
  readWithAi(text, { provider: "near-ai-cloud", ...cfg }, fetchImpl);

export async function readWithAi(
  text: string,
  cfg: AiConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<{ action: Action; evidence: AiEvidence }> {
  const near = cfg.provider === "near-ai-cloud";
  const body = JSON.stringify({
    model: cfg.model,
    messages: [
      { role: "system", content: SYSTEM },
      { role: "user", content: text.slice(0, 2000) },
    ],
    temperature: 0,
    stream: false,
  });
  const res = await fetchImpl(`${cfg.base}/chat/completions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${cfg.apiKey}`,
      "accept-encoding": "identity",
      ...(near ? { "x-no-aliasing": "true" } : {}),
    },
    body,
    signal: AbortSignal.timeout(20_000),
  });
  const raw = new Uint8Array(await res.arrayBuffer());
  if (!res.ok) throw new Error(`${near ? "NEAR AI Cloud" : "OpenAI"} answered ${res.status}`);
  const json = JSON.parse(Buffer.from(raw).toString()) as { id?: string; model?: string; choices?: { message?: { content?: string } }[] };
  const content = json.choices?.[0]?.message?.content ?? "";
  const chatId = json.id ?? null;
  const evidence: AiEvidence = {
    provider: cfg.provider,
    model: json.model ?? cfg.model,
    chatId,
    signature: { status: "unavailable", algo: "ecdsa" },
    attestation: "not checked",
  };
  // Only NEAR AI Cloud signs its answers; OpenAI's stay "unavailable".
  if (near && chatId) evidence.signature = await checkSignature(chatId, cfg, sha256(body), sha256(raw), fetchImpl);
  return { action: toAction(content), evidence };
}

async function checkSignature(
  chatId: string,
  cfg: { apiKey: string; model: string; base: string },
  requestHash: string,
  responseHash: string,
  fetchImpl: typeof fetch,
): Promise<AiEvidence["signature"]> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const r = await fetchImpl(`${cfg.base}/signature/${chatId}?signing_algo=ecdsa`, {
        headers: { authorization: `Bearer ${cfg.apiKey}`, accept: "application/json" },
        signal: AbortSignal.timeout(8_000),
      });
      if (r.status === 404) {
        await new Promise((ok) => setTimeout(ok, 1000));
        continue;
      }
      const s = (await r.json()) as { text?: string; signature?: string; signing_address?: string; signature_kind?: string; error_code?: string };
      if (!s.text || !s.signature || !s.signing_address) return { status: "unavailable", algo: "ecdsa" };
      const expected = s.signature_kind === "gateway" ? `${requestHash}:${responseHash}` : `${cfg.model}:${requestHash}:${responseHash}`;
      const signer = await recoverMessageAddress({ message: s.text, signature: s.signature as `0x${string}` });
      const ok = s.text === expected && signer.toLowerCase() === s.signing_address.toLowerCase();
      return { status: ok ? "verified" : "mismatch", kind: s.signature_kind, signingAddress: s.signing_address, algo: "ecdsa" };
    } catch {
      return { status: "unavailable", algo: "ecdsa" };
    }
  }
  return { status: "unavailable", algo: "ecdsa" };
}

export function toAction(content: string): Action {
  const m = content.match(/\{[\s\S]*\}/);
  if (!m) return { kind: "unknown", reason: "The AI didn't find an action." };
  try {
    const j = JSON.parse(m[0]) as Record<string, string>;
    if (j.kind === "pay" && j.receiver && /^\d+(\.\d+)?$/.test(String(j.amount_near))) {
      return { kind: "pay", receiver: String(j.receiver).toLowerCase(), amountNear: String(j.amount_near), ...(j.memo ? { memo: String(j.memo).slice(0, 140) } : {}) };
    }
    if (j.kind === "swap" && /^\d+(\.\d+)?$/.test(String(j.amount_usd)) && j.from && j.to) {
      return { kind: "swap", amount: String(j.amount_usd), from: String(j.from).toUpperCase(), to: String(j.to).toUpperCase(), usd: true };
    }
    if (j.kind === "swap" && /^\d+(\.\d+)?$/.test(String(j.amount)) && j.from && j.to) {
      return { kind: "swap", amount: String(j.amount), from: String(j.from).toUpperCase(), to: String(j.to).toUpperCase() };
    }
  } catch {
    /* fall through */
  }
  return { kind: "unknown", reason: "The AI didn't find an action." };
}
