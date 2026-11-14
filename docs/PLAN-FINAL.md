# Keybots: what it is, how it works, what's left

Written 14 Nov 2026, ~11:10 UTC. Feature freeze 14:00 UTC, deadline 23:59 UTC.

## 1. What Keybots is, in one line

A phone keyboard where AI agents can pay and trade for you, but only inside limits a NEAR contract enforces.

## 2. How it works (plain)

```
 You type / paste / follow          Keybots server                       NEAR (testnet)
 ─────────────────────────          ──────────────                       ──────────────
 "pay harshal 0.2"   ──typed──▶  Pay Agent   (pay.…)      ──asks──▶  ┌─────────────────┐
 a pasted message    ──pasted─▶  Inbox Agent (inbox.…)    ──asks──▶  │  Spend Limits   │──▶ pays / refuses
 a call on X / TG    ──review─▶  Trading Agent (trader.…) ──asks──▶  │  (the contract) │──▶ swaps on Rhea
                                                                      └─────────────────┘
 "hold space"        ──────────▶ NEAR AI Cloud (private AI, signed answers)   — never touches money
```

- **Spend Limits** (the contract) holds the money. Every payment and swap is checked on chain, in order: Stop everything → blocked list → per-payment limit → daily limit → allowed list (untrusted agent only) → your Face ID approval. Every refusal is an on-chain event.
- **The three agents** are just NEAR accounts with one narrow key each. They can only *ask* Spend Limits; they can't move money themselves.
  - **Pay Agent**: what you type. Trusted, up to 0.5 NEAR a payment, 1 a day.
  - **Inbox Agent**: what you paste. Untrusted: can only pay accounts you allowed; anything new waits for your Face ID.
  - **Trading Agent**: swaps. Up to 1 NEAR a trade, 2 a day. Only runs after you review and hold to confirm.
- **The AI** (rewrite, reply, translate, ask, search) is NOT an agent with money. It runs on NEAR AI Cloud; each answer's signature and the hardware attestation are checked. Money text is never sent to it.
- **Honest limit:** "typed" vs "pasted" is decided by the keyboard and server, not the contract.

## 3. What NEAR is used for

| NEAR piece | What we use it for |
|---|---|
| A Rust contract (Spend Limits) | Holds funds, decides every payment and swap |
| Sub-accounts | One account per agent |
| Function-call keys | Agents can only call the contract, nothing else |
| Owner key on the phone | Approvals and Stop everything, signed after Face ID |
| Rhea | The actual swaps on testnet (pool 1103 NEAR/USDC) |
| NEAR Intents (1Click) | Token list, prices, checks that a coin in a post is real |
| NEAR AI Cloud | The private AI |
| On-chain events | Every decision is public and linkable |

## 4. Features today

- **Keyboard:** normal typing, swipe, autocorrect, emoji, clipboard, GIFs; hold P/S/C/V for actions; hold space for the AI panel; the agent strip (pay, warnings on pasted addresses).
- **Calls:** posts from X (via Kall) and Telegram (your bot's group) → Review trade → hold → receipt.
- **App:** Wallet, Spend Limits (agents, limits, Stop everything, approvals, lists), Activity, Following.
- **Public:** the live contract page `/limits`, a keyless `npm run try`.

## 5. What Kall Markets does better (from its screenshots; ideas only, no code or assets copied)

1. **One clear "connected" page**: partners as big cards with On/Live. → We should show NEAR Intents, Rhea, NEAR AI Cloud, Kall (X), Telegram the same way.
2. **One big number**: "You pay 25 / You get 0.011214", token + chain pills. → Our review card is close; make the numbers bigger.
3. **One chip in the strip** for what you typed ("DCA $20 of ETH monthly · Set"). → Ours exists; keep it to one chip, no extra lines.
4. **A confirmation in the Dynamic Island** ("Placed"). → Nice, but not before the freeze.
5. **A home that explains the keys** ("11 keys bound"). → Our app should show the hold keys the same way.

## 6. X and Telegram: the architecture

```
 X (people Kall tracks) ──Kall API──┐
                                    ├──▶ server: read by fixed rules (spot buy/sell only;
 Telegram group ──your bot──────────┘       no perps, no contract addresses) ──▶ /v1/kol/feed
                                                                                     │
 keyboard Calls › Posts  ◀─────────────────────────────────────────────────────────┘
   card: who · where (X / Telegram) · when · the post · "Review trade"
   → /v1/trade/review (Rhea quote, minimum, your limits, 30 s)
   → hold → /v1/trade/confirm (once) → Trading Agent → Spend Limits → receipt + tx link
```
Nothing trades on its own. Posts are only ever displayed and read by fixed rules; never sent to the AI.

## 7. The to-do list (in order; one at a time)

| # | Task | Why |
|---|---|---|
| 1 | **Keyboard cleanup**: remove AI noise from the strip and menu; Calls (X + Telegram) is the main money screen; swap stays but is secondary | You asked: clean, no slop |
| 2 | **App: Agents screen**: the three agents as clear cards (what each may do, its limit, today's spend, its last action) + Stop everything | Makes the agents understandable |
| 3 | **App: Connected page**: NEAR Intents, Rhea, NEAR AI Cloud, Kall (X), Telegram, each with live status | Shows NEAR use clearly, like Kall Markets' |
| 4 | **NEAR Intents view**: what it checked for a call (real token, price), shown on the review card in one line | You asked to show Intents properly |
| 5 | **Telegram live check**: you post in the group; I confirm the card appears | Demo needs it |
| 6 | **Short clips for the README**: screen recordings (5–10 s each): follow on X → post appears → review → hold → receipt; Telegram post → card; Stop everything | You asked for "how it works" clips |
| 7 | **Screenshots everywhere** in the README, app and keyboard, light and dark | Judges skim |
| 8 | **README rewrite** around sections 2–6 above | One page that explains it |
| 9 | **Video**: tell the Social agent to replace the fake Telegram scene with the real group | Honesty |
| 10 | **Push to GitHub** (needs your yes) | Nothing is pushed since this morning |
| 11 | **Mainnet swap** (needs your yes) | One real trade |

On commits: every task above lands as many small, real commits (one per change). I won't make empty or fake commits to raise the count.
