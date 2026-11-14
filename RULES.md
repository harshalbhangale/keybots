# Spend Limits: rules

AirKey is one assistant with three lanes: what you type, messages you copy, and trades. Each lane is its own NEAR account (an "agent" in the code). An agent can move money only by calling Spend Limits, a NEAR contract, and Spend Limits decides. These are the rules it enforces. The code is `contracts/leash/src/lib.rs` (the contract is called the leash in the code and in its testnet account name); every rule below has a test there.

## Who is who

- **Owner:** the person. Owns Spend Limits, holds a full-access key in the AirKey app, and is the only one who can change rules, approve, or withdraw.
- **Agent:** a NEAR sub-account for one lane: `pay.<you>` (your words), `inbox.<you>` (messages you copy), `trader.<you>` (trades). It signs with a **function-call access key that can only call Spend Limits**, so it cannot send NEAR or add keys on its own. The owner registers each agent with a trust tier and limits.
- **Trust tier**, fixed per agent by the owner, never chosen per request:
  - `trusted`: acts on what the owner typed in the AirKey keyboard.
  - `untrusted`: acts on text that came from someone else (a pasted message, a copied post, later an email).

## What happens when an agent asks to pay

`pay(receiver, amount, memo)` is checked in this order. The first rule that fires decides.

| # | Rule | Result |
|---|---|---|
| R1 | The kill switch is on | **blocked** |
| R2 | The caller is not a registered agent | panic (nothing happens) |
| R3 | The receiver is on the blocklist | **blocked** |
| R4 | The amount is above the agent's per-payment cap | **blocked** |
| R5 | The amount would take the agent past its daily cap | **blocked** |
| R6 | The agent is `untrusted` and the receiver is not on the owner's allowlist | **pending**: waits for the owner |
| R7 | The agent asked for approval (`ask_owner: true`), for example because the off-chain check warned | **pending** |
| R0 | Spend Limits doesn't hold enough NEAR (balance minus what its storage needs) | **blocked** |
| - | Otherwise | **paid**: Spend Limits sends the NEAR |

- A day is a UTC day by block time. Spending resets at 00:00 UTC.
- If a transfer fails (for example the receiver doesn't exist), the spend is rolled back and a `transfer_failed` event is logged.
- Pending payments reserve nothing. When the owner approves, R1 and R3 are checked again, and the amount counts toward that agent's daily spend. The owner may approve above the per-payment cap; that is the point of asking.
- The owner can reject a pending payment, and it is gone.

## What only the owner can do

Add or remove agents and set their tier and caps; add to or remove from the allowlist; block or unblock an account (with a reason); turn the kill switch on or off; approve or reject pending payments; withdraw funds.

## The blocklist

Agents can also report an account with evidence (`report(account, evidence)`). A report puts the account on the blocklist straight away, because a false block costs a delayed payment, while a missed one costs money. The owner can unblock.

## Receipts

Every decision is logged as a NEP-297 event (`standard: "airkey"`): `paid`, `pending`, `blocked`, `approved`, `rejected`, `transfer_failed`, `reported`, `swap`, plus the owner's rule changes. Anyone can read them from the chain.

## Swaps

`swap(venue, amount, wrap, msg, memo, sell)` runs on testnet today, on Rhea:

- Only the Trading Agent (`trader.<you>`) can swap: its key may call `pay`, `report` and `swap`; the other agents' keys may call only `pay` and `report`. The server also refuses any trade from pasted text.
- A swap is checked like a payment: kill switch, blocklist, the agent's per-payment and daily caps, and what Spend Limits holds. A swap never waits for approval; it is either within the caps or blocked. Trading never uses up what the payment lanes may spend.
- Spend Limits wraps exactly the amount into wNEAR (only through `wrap.near` or `wrap.testnet`) and hands it to the venue. The token comes back to Spend Limits, so value never leaves it. If anything fails, the spend is rolled back.
- Off chain, the server first checks both tokens against NEAR Intents' own token list, so a look-alike symbol is refused.

On mainnet the same method funds a NEAR Intents deposit address instead; Spend Limits has enforced no mainnet swap yet.

## Spend Limits Lite (mainnet)

On mainnet, Spend Limits Lite runs at `limits.hellbuddy.near` (code in `contracts/limits-lite/`). It checks payments with the same rules in the same order (R1–R7, then R0), with two differences: R6 and R7 stop the payment instead of leaving it waiting for the owner, and it has no swaps.

## What Spend Limits does not do

- It does not judge who a new receiver is. Account age, contract code changes and past payments are checked off-chain by the AirKey server before it calls `pay`, and it passes `ask_owner: true` when the check warns.
- It does not keep the agents' keys. The server does (see README). Spend Limits is what limits a stolen key to the caps above.
