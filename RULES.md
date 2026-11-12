# The leash: rules

AirKey gives each AI agent its own NEAR account. The agent can move money only by calling the leash contract, and the leash decides. These are the rules it enforces. The code is `contracts/leash/src/lib.rs`; every rule below has a test there.

## Who is who

- **Owner:** the person. Owns the leash, holds a full-access key in the AirKey app, and is the only one who can change rules, approve, or withdraw.
- **Agent:** a NEAR sub-account such as `pay.harshal.airkey.testnet`. It signs with a **function-call access key that can only call this leash**, so it cannot send NEAR or add keys on its own. The owner registers each agent with a trust tier and limits.
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
| R0 | The leash doesn't hold enough NEAR (balance minus what its storage needs) | **blocked** |
| - | Otherwise | **paid**: the leash sends the NEAR |

- A day is a UTC day by block time. Spending resets at 00:00 UTC.
- If a transfer fails (for example the receiver doesn't exist), the spend is rolled back and a `transfer_failed` event is logged.
- Pending payments reserve nothing. When the owner approves, R1 and R3 are checked again, and the amount counts toward that agent's daily spend. The owner may approve above the per-payment cap; that is the point of asking.
- The owner can reject a pending payment, and it is gone.

## What only the owner can do

Add or remove agents and set their tier and caps; add to or remove from the allowlist; block or unblock an account (with a reason); turn the kill switch on or off; approve or reject pending payments; withdraw funds.

## The blocklist

Agents can also report an account with evidence (`report(account, evidence)`). A report puts the account on the blocklist straight away, because a false block costs a delayed payment, while a missed one costs money. The owner can unblock.

## Receipts

Every decision is logged as a NEP-297 event (`standard: "airkey"`): `paid`, `pending`, `blocked`, `approved`, `rejected`, `transfer_failed`, `reported`, plus the owner's rule changes. Anyone can read them from the chain.

## What the leash does not do

- It does not judge who a new receiver is. Account age, contract code changes and past payments are checked off-chain by the AirKey server before it calls `pay`, and it passes `ask_owner: true` when the check warns.
- It does not keep the agents' keys. The server does (see README). The leash is what limits a stolen key to the caps above.
