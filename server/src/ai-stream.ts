// Streamed answers for the keyboard's AI: the words arrive as they are
// written. The same AIs and the same order as everything else here: NEAR AI
// Cloud (private, signed) first, OpenAI only when it is allowed and NEAR AI
// isn't set up or doesn't answer. The signature is checked over the exact
// bytes of the stream once it ends, so a streamed answer carries the same
// evidence as a whole one.
import { createHash } from "node:crypto";
import type { FastifyReply } from "fastify";
import { chatWithEvidence, checkSignature, type AiConfig, type AiEvidence, type ChatMessage } from "./ai.js";
import { attestations } from "./attest.js";

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest("hex");

export class AiUnavailable extends Error {}

export interface StreamHandlers {
  /** Each piece of the answer as it comes. */
  onToken?: (t: string) => void;
  /** The AI that was writing stopped; the next one starts the answer over. */
  onRestart?: () => void;
  temperature?: number;
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
  /** How long one AI gets, start to finish. */
  timeoutMs?: number;
}

/** Who answered, in the words every reply carries. */
export interface Answered {
  provider: AiConfig["provider"];
  model: string;
  signature: AiEvidence["signature"]["status"];
  attestation: AiEvidence["attestation"];
}

export const answered = (e: AiEvidence): Answered => ({ provider: e.provider, model: e.model, signature: e.signature.status, attestation: e.attestation });

/** Lets the answer through and holds back a model's <think>…</think> working. */
export class ThinkFilter {
  private held = "";
  private thinking = false;
  constructor(private readonly emit: (t: string) => void) {}

  push(token: string): void {
    this.held += token;
    for (;;) {
      if (this.thinking) {
        const end = this.held.indexOf("</think>");
        if (end < 0) {
          this.held = this.held.slice(-8); // enough to catch a tag split across pieces
          return;
        }
        this.held = this.held.slice(end + 8);
        this.thinking = false;
      } else {
        const start = this.held.indexOf("<think>");
        if (start >= 0) {
          if (start > 0) this.emit(this.held.slice(0, start));
          this.held = this.held.slice(start + 7);
          this.thinking = true;
          continue;
        }
        // Keep back a tail that could be the start of "<think>".
        const lt = this.held.lastIndexOf("<");
        const safe = lt >= 0 && "<think>".startsWith(this.held.slice(lt)) ? lt : this.held.length;
        if (safe > 0) this.emit(this.held.slice(0, safe));
        this.held = this.held.slice(safe);
        return;
      }
    }
  }

  flush(): void {
    if (!this.thinking && this.held) this.emit(this.held);
    this.held = "";
  }
}

/** One streamed chat completion from one AI, with its evidence. */
export async function streamOne(messages: ChatMessage[], cfg: AiConfig, h: StreamHandlers = {}): Promise<{ content: string; evidence: AiEvidence }> {
  const fetchImpl = h.fetchImpl ?? fetch;
  const near = cfg.provider === "near-ai-cloud";
  const body = JSON.stringify({ model: cfg.model, messages, temperature: h.temperature ?? 0.3, stream: true });
  const timeout = AbortSignal.timeout(h.timeoutMs ?? 30_000);
  const res = await fetchImpl(`${cfg.base}/chat/completions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${cfg.apiKey}`,
      "accept-encoding": "identity",
      ...(near ? { "x-no-aliasing": "true" } : {}),
    },
    body,
    signal: h.signal ? AbortSignal.any([h.signal, timeout]) : timeout,
  });
  if (!res.ok || !res.body) throw new Error(`${near ? "NEAR AI Cloud" : "OpenAI"} answered ${res.status}`);

  const hash = createHash("sha256");
  const decoder = new TextDecoder();
  let pending = "";
  let content = "";
  let chatId: string | null = null;
  let model = cfg.model;
  const filter = new ThinkFilter((t) => {
    content += t;
    h.onToken?.(t);
  });
  const line = (l: string) => {
    if (!l.startsWith("data:")) return;
    const data = l.slice(5).trim();
    if (!data || data === "[DONE]") return;
    try {
      const j = JSON.parse(data) as { id?: string; model?: string; choices?: { delta?: { content?: string } }[] };
      chatId ??= j.id ?? null;
      if (j.model) model = j.model;
      const t = j.choices?.[0]?.delta?.content;
      if (t) filter.push(t);
    } catch {
      // A line that isn't JSON carries no words.
    }
  };
  for await (const chunk of res.body as unknown as AsyncIterable<Uint8Array>) {
    hash.update(chunk);
    pending += decoder.decode(chunk, { stream: true });
    let nl: number;
    while ((nl = pending.indexOf("\n")) >= 0) {
      line(pending.slice(0, nl).trimEnd());
      pending = pending.slice(nl + 1);
    }
  }
  line(pending.trim());
  filter.flush();

  const evidence: AiEvidence = {
    provider: cfg.provider,
    model,
    chatId,
    signature: { status: "unavailable", algo: "ecdsa" },
    attestation: "not checked",
  };
  // Only NEAR AI Cloud signs its answers; OpenAI's stay "unavailable".
  if (near && chatId) evidence.signature = await checkSignature(chatId, cfg, sha256(body), hash.digest("hex"), fetchImpl);
  if (near) Object.assign(evidence, attestations.evidenceFor(cfg.model, evidence.signature));
  return { content: content.trim(), evidence };
}

/**
 * A streamed answer from the first AI that gives one. `readers` comes from
 * aiReaders(cfg). When one stops midway, onRestart says so and the next
 * starts over.
 */
export async function streamChat(messages: ChatMessage[], readers: AiConfig[], h: StreamHandlers = {}): Promise<{ content: string; evidence: AiEvidence }> {
  if (readers.length === 0) throw new AiUnavailable("AI isn't set up on this server");
  let last: unknown;
  for (const ai of readers) {
    let wrote = false;
    try {
      const out = await streamOne(messages, ai, { ...h, onToken: (t) => { wrote = true; h.onToken?.(t); } });
      if (!out.content) throw new Error(`${ai.provider} answered with nothing`);
      return out;
    } catch (e) {
      last = e;
      if (h.signal?.aborted) break;
      if (wrote) h.onRestart?.();
    }
  }
  throw last instanceof Error ? last : new Error("The AI didn't answer");
}

/** A whole (not streamed) answer from the first AI that gives one. */
export async function askChat(
  messages: ChatMessage[],
  readers: AiConfig[],
  opts: { temperature?: number; fetchImpl?: typeof fetch } = {},
): Promise<{ content: string; evidence: AiEvidence }> {
  if (readers.length === 0) throw new AiUnavailable("AI isn't set up on this server");
  let last: unknown;
  for (const ai of readers) {
    try {
      const out = await chatWithEvidence(messages, ai, opts.fetchImpl ?? fetch, opts.temperature ?? 0);
      const content = out.content.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
      if (!content) throw new Error(`${ai.provider} answered with nothing`);
      return { content, evidence: out.evidence };
    } catch (e) {
      last = e;
    }
  }
  throw last instanceof Error ? last : new Error("The AI didn't answer");
}

/** Server-sent events on a Fastify reply: open it, then send named events. */
export function openEvents(reply: FastifyReply): { send: (event: string, data: unknown) => void; end: () => void; gone: AbortSignal } {
  reply.hijack();
  reply.raw.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache, no-transform",
    connection: "keep-alive",
    "x-accel-buffering": "no",
    "access-control-allow-origin": "*",
  });
  reply.raw.flushHeaders?.();
  const abort = new AbortController();
  // The keyboard closed the bar: stop asking the AI.
  reply.raw.on("close", () => {
    if (!reply.raw.writableEnded) abort.abort();
  });
  return {
    send: (event, data) => {
      if (!reply.raw.writableEnded) reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    },
    end: () => {
      if (!reply.raw.writableEnded) reply.raw.end();
    },
    gone: abort.signal,
  };
}
