import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { memoryVault, vaultProblem } from "../src/vault.js";

const app = () => buildApp({ cfg: loadConfig({}), vault: memoryVault() } as never);

describe("the vault", () => {
  it("saves what the app sends and gives it back to the keyboard", async () => {
    const a = app();
    const items = [{ id: "1", label: "UPI", value: "harshal@okicici" }];
    expect((await a.inject({ method: "PUT", url: "/v1/vault", payload: { items } })).statusCode).toBe(200);
    expect((await a.inject({ method: "GET", url: "/v1/vault" })).json()).toEqual({ items });
  });

  it("refuses secrets", async () => {
    const a = app();
    const key = "0x" + "ab".repeat(32);
    const res = await a.inject({ method: "PUT", url: "/v1/vault", payload: { items: [{ id: "1", label: "k", value: key }] } });
    expect(res.statusCode).toBe(400);
    expect((await a.inject({ method: "GET", url: "/v1/vault" })).json()).toEqual({ items: [] });
    expect(vaultProblem(Array(12).fill("word").join(" "))).toMatch(/recovery phrase/);
    expect(vaultProblem("ed25519:" + "x".repeat(80))).toMatch(/private key/);
    expect(vaultProblem("0x" + "ab".repeat(20))).toBeNull();
  });
});
