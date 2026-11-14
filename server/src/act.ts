// The keyboard's older one-shot AI bar (POST /v1/act), kept for the app's
// API.swift. Each action runs as one of the streamed assist tasks
// (assist.ts) and only the final text comes back, with who answered.
import type { AiConfig, AiEvidence } from "./ai.js";
import { ASSIST_MAX, AssistFail, languageName, looksLikeMoney, runAssist, type Task } from "./assist.js";

export const ACT_ACTIONS = ["rewrite", "reply", "translate", "tone", "ask"] as const;
export type ActAction = (typeof ACT_ACTIONS)[number];

/** The most text one act reads. Longer input is cut to its first 2000 characters. */
export const ACT_MAX = ASSIST_MAX;

export interface ActRequest {
  text: string;
  action: ActAction;
  tone?: string;
  language?: string;
}

export interface ActResult {
  text: string;
  provider: AiConfig["provider"];
  model: string;
  signature: AiEvidence["signature"]["status"];
  attestation: AiEvidence["attestation"];
}

export class ActUnavailable extends Error {}
/** The text reads as money: no AI is asked. */
export class ActMoney extends Error {}

/** rewrite → fix, reply → the first reply, tone → warmer (or formal / shorter when asked for). */
export function taskFor(req: ActRequest): Task {
  switch (req.action) {
    case "rewrite":
      return "fix";
    case "tone": {
      const t = (req.tone ?? "").toLowerCase();
      return /formal|professional/.test(t) ? "formal" : /short|brief/.test(t) ? "shorter" : "warmer";
    }
    default:
      return req.action;
  }
}

export async function act(req: ActRequest, readers: AiConfig[], fetchImpl?: typeof fetch): Promise<ActResult> {
  if (readers.length === 0) throw new ActUnavailable("AI isn't set up on this server");
  const text = req.text.trim().slice(0, ACT_MAX);
  if (looksLikeMoney(text)) throw new ActMoney();
  try {
    const done = await runAssist(
      { task: taskFor(req), text, language: languageName(req.language), source: "typed" },
      { readers, serperKey: "", fetchImpl },
      () => {},
    );
    const r = done.receipt;
    return { text: done.text, provider: r.provider, model: r.model, signature: r.signature, attestation: r.attestation };
  } catch (e) {
    if (e instanceof AssistFail) throw new Error(e.message);
    throw e;
  }
}
