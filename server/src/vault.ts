// The vault: things you share often (a UPI ID, an EVM address), saved in the
// app and offered by the keyboard. With free Apple signing the two can't share
// an App Group, so the app sends the list here and the keyboard reads it back.
// Only safe-to-share values: anything that looks like a secret is refused,
// the same checks as ios/Shared/Vault.swift.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export interface VaultItem {
  id: string;
  label: string;
  value: string;
}

export interface VaultStore {
  list(): VaultItem[];
  save(items: VaultItem[]): void;
}

const MAX_ITEMS = 50;
const MAX_LABEL = 60;
const MAX_VALUE = 300;

/** Why a value can't go in the vault, or null when it can. */
export function vaultProblem(value: string): string | null {
  const v = value.trim();
  if (!v) return "Add the address or ID to share.";
  const words = v.split(/\s+/);
  if (words.length >= 12 && words.every((w) => /^\p{L}+$/u.test(w))) return "That looks like a recovery phrase. Never put one in a keyboard.";
  const r = v.indexOf("ed25519:");
  if (r >= 0 && v.slice(r + 8).length > 60) return "That looks like a private key. Only add things that are safe to share.";
  const hex = v.startsWith("0x") ? v.slice(2) : v;
  if (hex.length === 64 && /^[0-9a-fA-F]+$/.test(hex)) return "That looks like a private key. Only add things that are safe to share.";
  return null;
}

/** Checks a list sent by the app. Throws a plain-words message when it can't be saved. */
export function parseVault(body: unknown): VaultItem[] {
  const items = (body as { items?: unknown })?.items;
  if (!Array.isArray(items)) throw new Error("Send { items: [...] }.");
  if (items.length > MAX_ITEMS) throw new Error(`At most ${MAX_ITEMS} items.`);
  return items.map((raw) => {
    const it = raw as Partial<VaultItem>;
    if (typeof it?.id !== "string" || typeof it.label !== "string" || typeof it.value !== "string") throw new Error("Each item needs an id, a label and a value.");
    const label = it.label.trim().slice(0, MAX_LABEL);
    const value = it.value.trim();
    if (value.length > MAX_VALUE) throw new Error("That value is too long.");
    const problem = vaultProblem(value);
    if (problem) throw new Error(problem);
    return { id: it.id.slice(0, 64), label, value };
  });
}

export function fileVault(dir: string): VaultStore {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, "vault.json");
  return {
    list: () => (existsSync(file) ? (JSON.parse(readFileSync(file, "utf8")) as VaultItem[]) : []),
    save: (items) => writeFileSync(file, JSON.stringify(items, null, 2), { mode: 0o600 }),
  };
}

export function memoryVault(): VaultStore {
  let all: VaultItem[] = [];
  return { list: () => all, save: (items) => void (all = items) };
}
