// One streamed chat answer and its evidence. NEAR AI Cloud and OpenAI both
// speak the same chat API; with `stream: true` the answer comes back as
// server-sent events, one small piece of text per `data:` line.
//
// The evidence is the same as ai.ts keeps for answers that aren't streamed:
// we keep every byte of the request and of the event stream exactly as sent
// and received, hash both, and ask NEAR AI Cloud for its signature over those
// two hashes. Then the cached hardware attestation (attest.ts) is attached,
// with whether this answer's signer is the attested one.
import { createHash } from "node:crypto";
import { checkSignature, type AiConfig, type AiEvidence, type ChatMessage } from "./ai.js";
import { attestations } from "./attest.js";

export interface StreamOptions {
  temperature: number;
  maxTokens: number;
  fetchImpl?: typeof fetch;
  /** Stops the answer when the person goes away. */
  signal?: AbortSignal;
  /** How long one answer may take, start to end. */
  timeoutMs?: number;
}

export interface Streamed {
  text: string;
  evidence: AiEvidence;
}

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

/** A provider that failed before saying anything: the next one may be asked. */
export class NoAnswer extends Error {}

/**
 * Ask one AI and pass each piece of text to `onText` as it arrives. Resolves
 * with the whole text and its evidence once the stream ends.
 */
export async function streamAnswer(
  messages: ChatMessage[],
  ai: AiConfig,
  onText: (piece: string) => void,
  opts: StreamOptions,
): Promise<Streamed> {
  const near = ai.provider === "near-ai-cloud";
  const who = near ? "NEAR AI Cloud" : "OpenAI";
  const fetchImpl = opts.fetchImpl ?? fetch;
  const body = JSON.stringify({
    model: ai.model,
    messages,
    temperature: opts.temperature,
    max_tokens: opts.maxTokens,
    stream: true,
  });
  const timeout = AbortSignal.timeout(opts.timeoutMs ?? 25_000);
  const signal = opts.signal ? AbortSignal.any([opts.signal, timeout]) : timeout;

  let res: Response;
  try {
    res = await fetchImpl(`${ai.base}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "text/event-stream",
        authorization: `Bearer ${ai.apiKey}`,
        "accept-encoding": "identity",
        ...(near ? { "x-no-aliasing": "true" } : {}),
      },
      body,
      signal,
    });
  } catch (e) {
    throw new NoAnswer(`${who} didn't answer: ${String((e as Error).message ?? e).slice(0, 120)}`);
  }
  if (!res.ok || !res.body) {
    await res.body?.cancel().catch(() => {});
    throw new NoAnswer(`${who} answered ${res.status}`);
  }

  const raw: Uint8Array[] = [];
  const decoder = new TextDecoder();
  let pending = "";
  let text = "";
  let id: string | null = null;
  let model: string | null = null;

  const readLine = (line: string) => {
    if (!line.startsWith("data:")) return;
    const data = line.slice(5).trim();
    if (!data || data === "[DONE]") return;
    let json: { id?: string; model?: string; choices?: { delta?: { content?: string | null } }[] };
    try {
      json = JSON.parse(data);
    } catch {
      return;
    }
    id ??= json.id ?? null;
    model ??= json.model ?? null;
    const piece = json.choices?.[0]?.delta?.content;
    if (piece) {
      text += piece;
      onText(piece);
    }
  };

  const reader = res.body.getReader();
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      raw.push(value);
      pending += decoder.decode(value, { stream: true });
      let nl: number;
      while ((nl = pending.indexOf("\n")) >= 0) {
        readLine(pending.slice(0, nl).replace(/\r$/, ""));
        pending = pending.slice(nl + 1);
      }
    }
    pending += decoder.decode();
    if (pending) readLine(pending.trim());
  } catch (e) {
    const msg = `${who} stopped mid-answer: ${String((e as Error).message ?? e).slice(0, 120)}`;
    throw text ? new Error(msg) : new NoAnswer(msg);
  }
  if (!text.trim()) throw new NoAnswer(`${who} answered with nothing`);

  const evidence: AiEvidence = {
    provider: ai.provider,
    model: model ?? ai.model,
    chatId: id,
    signature: { status: "unavailable", algo: "ecdsa" },
    attestation: "not checked",
  };
  if (near && id) {
    const bytes = Buffer.concat(raw);
    evidence.signature = await checkSignature(id, ai, sha256(body), sha256(bytes), fetchImpl);
  }
  if (near) Object.assign(evidence, attestations.evidenceFor(ai.model, evidence.signature));
  return { text, evidence };
}

/**
 * The first AI in `readers` that answers. One that fails before any text has
 * gone out is passed over for the next; once text has gone out, a failure is
 * the answer's failure.
 */
export async function streamFirst(
  messages: ChatMessage[],
  readers: AiConfig[],
  onText: (piece: string) => void,
  opts: StreamOptions,
): Promise<Streamed> {
  let last: unknown = new Error("No AI is set up");
  for (const ai of readers) {
    try {
      return await streamAnswer(messages, ai, onText, opts);
    } catch (e) {
      last = e;
      if (!(e instanceof NoAnswer) || opts.signal?.aborted) break;
    }
  }
  throw last;
}
