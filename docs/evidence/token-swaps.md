# Token swaps from the leash (testnet)

Run on 2026-11-13 against a second leash, [`leash2.airkey-harshal.testnet`](https://testnet.nearblocks.io/address/leash2.airkey-harshal.testnet), which runs the new contract code. The live leash (`leash.airkey-harshal.testnet`) was not touched.

T = `https://testnet.nearblocks.io/txns/`

## What the contract does now

`swap` takes an optional `sell: { token, amount, unwrap }`. With it, the leash sends a token it holds to the venue by `ft_transfer_call` instead of wrapping NEAR, and `amount` is what the trade is worth in NEAR.

- **R8, token rules.** The owner sets one rule per token with `set_token_cap(token, max_per_trade, venue, min_value)`: the most one trade may sell, the only venue it may go to, and the least a full-size trade counts for in NEAR. No rule, more than the cap, or another venue: blocked.
- **Caps.** The leash has no price feed, so the agent states the value. The leash charges the larger of that and the owner's floor (`min_value × amount / max_per_trade`) against R4 and R5. R1, R2, R3 and R6 apply as for any swap. R0 doesn't: no NEAR leaves.
- **After.** `ft_transfer_call` says how much the venue used. Zero means it refused: the spend is rolled back and the token is still in the leash. With `unwrap`, the leash reads its wNEAR balance and withdraws all of it, so it holds NEAR again.
- **Why an argument and not a new method.** An agent's key names the methods it may call (`pay`, `report`, `swap`) and can't be changed. A new method would need new agent accounts; `swap` with `sell` works with the keys that exist, and sells nothing until the owner sets a token rule.

## Setup

| Step | Transaction |
|---|---|
| Create `leash2` with 4 NEAR | [3fSYSvVpPD…](https://testnet.nearblocks.io/txns/3fSYSvVpPD7UQK7N4oXyLBAHagX4iAWqDggTY5unWsKj) |
| Create `pay2`, `inbox2`, `trader2` (each with a function-call key for `leash2` only) | [RmhrisY5jG…](https://testnet.nearblocks.io/txns/RmhrisY5jG3qHcJjQjdkj1e5ANuGeFR6LHgGgrNNHQV), [BnoGcS2sXr…](https://testnet.nearblocks.io/txns/BnoGcS2sXrWFFB2vgkbYm58dQmrzp7yqLvn2mKwkz4KS), [4TupfYiDi5…](https://testnet.nearblocks.io/txns/4TupfYiDi5mwrg3bgHiTMJ76hKD4WR6WuuZHzZMdPmct) |
| Deploy (255,136 bytes, code hash `B8AwN1LnEru74NJWFiWQUMm81mB6gC75o54P431Vf5vC`) and init | [13w5vAXPkn…](https://testnet.nearblocks.io/txns/13w5vAXPknsDWBxi19NeYMC8FrVXjGH4eaxrWzsEBc5p) |
| Register `leash2` on wrap.testnet, USDC, USDT | [H7FK7NZ22T…](https://testnet.nearblocks.io/txns/H7FK7NZ22TKvFiGq5MyEvZ8AgPN1eChJ5KP94zPM59Ma), [B9FVhkm1Do…](https://testnet.nearblocks.io/txns/B9FVhkm1Do8Ln7RFQn22fTtBcc61amzJqruYWEGViqh3), [GYyDXkwvYR…](https://testnet.nearblocks.io/txns/GYyDXkwvYRJdNMMBbJVE1JZCpoJm3dmwYB3RYgzzfbck) |
| `set_token_cap` USDC: 5 a trade, Rhea only, 5 USDC counts for at least 1 NEAR | [F9D2vvhMwy…](https://testnet.nearblocks.io/txns/F9D2vvhMwys98dPx3RgLFMg9nzmJQ9ETfFR5fwBHkQv) |
| `set_token_cap` USDT: the same | [FEGuyt7ML6…](https://testnet.nearblocks.io/txns/FEGuyt7ML6RbgZMDqz1Bw4rVXabQMXdMxB6zmMfCjQQF) |

`trader2` has the live Trading Agent's caps: 1 NEAR a trade, 2 NEAR a day. The last three rows are `scripts/setup-token-swaps.mjs`; a second run sent nothing.

## The two swaps

Both typed into the server (`POST /v1/command`), signed by `trader2` with 200 TGas.

| Command | Receipt | Transaction |
|---|---|---|
| `swap 0.3 near to usdc` | Swapped 0.3 NEAR for 0.6302 USDC on Rhea. It's in the leash. | [31uMGBjVGF…](https://testnet.nearblocks.io/txns/31uMGBjVGFzkGS2zTXWmxz8CZE4g3HiqnbkTX4Ruq3vr) |
| `swap 0.5 usdc to near` | Swapped 0.5 USDC for 0.2365 NEAR on Rhea. It's in the leash. | [AsigncBn7D…](https://testnet.nearblocks.io/txns/AsigncBn7DGqKAvFENRE3g7g5KnZjy8cCKhtcKEfv8tF) |

The second one, on chain:

- `swap` event: 0.5 USDC, charged 0.141579 NEAR against the caps (NEAR Intents' price; the owner's floor would be 0.1).
- Rhea: `Swapped 500000000000000000000000 usdc.itachicara.testnet for 236574056859195782246576 wrap.testnet` in pool 1103, paid to the leash as wNEAR.
- `swapped`, then `unwrapped` 236574056859195782246576: wrap.testnet's `Withdraw … from leash2`.
- The whole transaction burnt 28.9 TGas of the 200 attached.

| `leash2` | Before | After |
|---|---|---|
| NEAR balance | 3.497974 | 3.734548 (+0.236574) |
| USDC | 0.630254 | 0.130254 |
| wNEAR | 0 | 0 |
| `trader2` spent today | 0.3 NEAR | 0.441579 NEAR |

Not run on chain (two swaps were the budget): USDC ↔ USDT and USDT → NEAR. They use the same contract path with another pool. The pools answer: 0.5 USDC → 0.2919 USDT and 0.5 USDT → 0.8528 USDC in pool 1126, 0.5 USDT → 0.4005 wNEAR in pool 1084 (`get_return`, 13 Nov).

## The nine end-to-end steps, on the new code

`scripts/e2e-testnet.mjs` against `leash2` (with `AIRKEY_LEASH` and `AIRKEY_AGENT_*` set): 9/9 as expected.

| # | Step | Expected | Got | Transaction |
|---|---|---|---|---|
| 1 | pay agent → friend 0.1 (typed) | paid | ✅ paid | [4a8qCJohSi…](https://testnet.nearblocks.io/txns/4a8qCJohSiK4xyn3bJiVbEHdMf9SpibfA5MsmmEXjomv) |
| 2 | inbox agent → vendor 0.1 (pasted invoice) | pending | ✅ pending (R6) | [FRkvYSr39s…](https://testnet.nearblocks.io/txns/FRkvYSr39szzqweDVX3BZN95r9n8cRejehinrm9oq9Rq) |
| 3 | injected: inbox agent → drain 5 | blocked | ✅ blocked (R4) | [E3sf3TGeP5…](https://testnet.nearblocks.io/txns/E3sf3TGeP5RE6exqjuhMDALoynE8XmbqEifjs28mYm5w) |
| 4 | after report: pay agent → drain 0.01 | blocked | ✅ blocked (R3) | [ExQUXwGB69…](https://testnet.nearblocks.io/txns/ExQUXwGB69WkXKQSjRMoiRiaZWJ8udRdzPnhrffRbJ8y) |
| 5 | owner approves the vendor invoice | paid | ✅ paid | [3ewAW2PmWh…](https://testnet.nearblocks.io/txns/3ewAW2PmWhx8QmapKXsn4sVbx5bGoGo3vzVwki2d4kdG) |
| 6 | pay agent signs a direct transfer to drain | rejected | ✅ rejected (Access key requires full access) | never reached the chain |
| 7 | pay agent calls set_paused | rejected | ✅ rejected (Access key does not allow method set_paused) | never reached the chain |
| 8 | pay to a missing account rolls back | rolled back | ✅ rolled back | [TA2pVYB2NG…](https://testnet.nearblocks.io/txns/TA2pVYB2NG1QpkpagGyNSR5YDm8h3xk6SEheYr6f9VS) |
| 9 | kill switch on: pay agent → friend | blocked | ✅ blocked (R1) | [AbYQZM8Mde…](https://testnet.nearblocks.io/txns/AbYQZM8Mdebfd7v1qK6xisGmKrET5EMjHUon5GoZS9V5) |

## Upgrading the live leash

**Is the new code compatible with the live leash's state? Yes; no migration.**

- The `Leash` struct has the same fields in the same order. Token rules are not a field: each is its own storage entry under a new prefix (`StorageKey::TokenRules`, byte `0x04`, then the token's account id). The existing prefixes (`0x00` to `0x03`) and `STATE` are untouched.
- Checked against the real thing: the test `reads_the_state_the_live_leash_wrote` holds the live leash's `STATE` entry (read with `view_state` on 13 Nov) and deserializes it with the new code: owner `airkey-harshal.testnet`, 6 agents, 1 allowlisted, 1 blocked, 0 pending, next id 12, and it serializes back byte for byte.
- `token_rules_live_outside_the_contract_state` checks that setting a token rule doesn't change `STATE`.
- Not checked: an actual upgrade of an account holding old state. `leash2` started empty.

**What changes for callers.** `swap` gains an optional `sell`; `pay`, `report`, `approve` and the views are as they were. The Trading Agent's key (`pay`, `report`, `swap`) needs no change. A server from before this change keeps working with the new contract. This server with the old contract only quotes token sales (it asks `get_token_cap` first and gets nothing).

**Storage.** The code is about 23 KB larger, so about 0.23 NEAR more of the leash's balance is held for storage: what it can spend drops from about 0.61 to about 0.38 NEAR until it is topped up.

**Commands** (from the repo root, with the keys in `keys/`):

```sh
cd contracts/leash && cargo test && cargo near build non-reproducible-wasm && cd ../..
cd scripts
npm run deploy -- airkey-harshal.testnet              # deploys the code to leash.airkey-harshal.testnet; state is kept
npm run setup-token-swaps -- airkey-harshal.testnet   # owner: USDC and USDT rules (5 a trade, Rhea only, floor 1 NEAR per 5)
```

The built wasm should have the code hash above. To undo: redeploy the previous wasm; the token rules it leaves behind are entries the old code never reads.

To point the server or the scripts at `leash2` instead: `AIRKEY_LEASH=leash2.airkey-harshal.testnet AIRKEY_AGENT_TRUSTED=pay2.airkey-harshal.testnet AIRKEY_AGENT_UNTRUSTED=inbox2.airkey-harshal.testnet AIRKEY_AGENT_TRADE=trader2.airkey-harshal.testnet`.
