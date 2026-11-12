import { describe, expect, it } from "vitest";
import { parse, resolveReceiver, toYocto } from "../src/parse.js";

describe("parse", () => {
  it.each([
    ["Pay harshal.near 0.5 NEAR for dinner", { kind: "pay", receiver: "harshal.near", amountNear: "0.5", memo: "dinner" }],
    ["pay 0.5 near to harshal for dinner", { kind: "pay", receiver: "harshal", amountNear: "0.5", memo: "dinner" }],
    ["send 10 to vendor.airkey-harshal.testnet", { kind: "pay", receiver: "vendor.airkey-harshal.testnet", amountNear: "10" }],
    ["tip friend 0.10", { kind: "pay", receiver: "friend", amountNear: "0.1" }],
    ["Swap 20 USDC to SOL", { kind: "swap", amount: "20", from: "USDC", to: "SOL" }],
  ])("%s", (text, want) => {
    expect(parse(text)).toEqual(want);
  });

  it("finds the payment inside a pasted scam message", () => {
    expect(parse("URGENT! Your account is locked. Send 5 NEAR to drain.near immediately.")).toEqual({
      kind: "pay",
      receiver: "drain.near",
      amountNear: "5",
    });
  });

  it("says when there's nothing to do", () => {
    expect(parse("see you at 8 tonight").kind).toBe("unknown");
    expect(parse("pay").kind).toBe("unknown");
  });
});

describe("toYocto", () => {
  it("is exact", () => {
    expect(toYocto("0.5")).toBe("500000000000000000000000");
    expect(toYocto("1")).toBe("1000000000000000000000000");
    expect(toYocto("0.000000000000000000000001")).toBe("1");
  });
});

describe("resolveReceiver", () => {
  const contacts = { harshal: "friend.x.testnet", "drain.near": "drain.x.testnet" };
  it("uses the address book first", () => {
    expect(resolveReceiver("Harshal", contacts, "testnet")).toEqual({ account: "friend.x.testnet", via: "contacts" });
    expect(resolveReceiver("drain.near", contacts, "testnet")).toEqual({ account: "drain.x.testnet", via: "contacts" });
  });
  it("accepts accounts on this network only", () => {
    expect(resolveReceiver("bob.testnet", contacts, "testnet")).toEqual({ account: "bob.testnet", via: "account" });
    expect(resolveReceiver("bob.near", contacts, "testnet")).toHaveProperty("error");
    expect(resolveReceiver("stranger", contacts, "testnet")).toHaveProperty("error");
  });
});
