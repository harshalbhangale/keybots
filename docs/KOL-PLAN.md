# Follow KOLs and trade their calls automatically

You follow people on X. When one of them posts a trade call, Keybots's Trading Agent buys or sells for you, within rules you set, and the contract still caps every trade.

## Where the calls come from
- **Kall's API** (kallmarkets.vercel.app, our own): `GET /api/keyboard/feed` lists 25 tracked callers and their open calls and results. `GET /api/callers/{handle}` returns one caller's calls and record (hit or miss, return), stored on Arkiv. No X API key needed.
- New posts are read by Kall's call reader (asset, buy or sell, confidence), the same reader as `server/src/calls.ts`.
- Honest limit: Kall sees the posts its users and extension see. It is not every post on X. Bringing in your whole X following list needs the paid X API, which comes later.

## What you set per KOL
- Auto on or off
- Dollars per call (default $1) and per day (default $3)
- Buy only, or buy and sell
- Only tokens verified on NEAR Intents (always on)
- Only calls the reader is sure of (high confidence)
- Stop following automatically after 3 misses in a row

## How a trade happens
1. The server checks each followed handle every 60 s.
2. A new call that passes your rules becomes a swap command (`swap $1 of near to sol`).
3. The Trading Agent sends it to the leash with the caps it already has on chain (1 NEAR a trade, 2 a day). No new agent and no contract change are needed.
4. On testnet there's no SOL or BTC, so the trade swaps NEAR to USDC on Rhea instead and says so, as the copied-call chip does today.
5. Every auto-trade gets a receipt naming the KOL and linking the post. Stop everything halts it.

What stays true: a message you copy still never trades. Only KOLs you followed, with rules you set, can trade, and the contract limits the damage if a KOL's account is hacked.

## Screens
- **Keyboard › Calls › Following:** add an @handle, see their record from Kall (hits, misses, average return), tap for rules, and turn auto on or off. Auto-trades appear in the list with their receipt.
- **App › Wallet:** the same list, plus a "Traded for you" history.

## Build (about 2 hours, two builders in parallel)
| Part | What | Time |
|---|---|---|
| Server | `follows.ts` (store, rules), a poller that reads Kall and runs the Trading Agent, `GET/POST/DELETE /v1/follows`, receipts with the KOL and post; tests with a fake Kall | 60–75 min |
| Keyboard + app | Following tab, rules sheet, auto toggle, "Traded for you" rows, haptics on a new auto-trade | 60–75 min |
| Me | merge, tests, phone build, one live auto-trade on testnet (with your OK) | 30 min |

## Demo beat (about 15 s)
Follow @CryptoKaleo with $1 per call → his latest call comes in → "Bought $1 of ETH for you (testnet: NEAR → USDC)", with the post link and the transaction.
