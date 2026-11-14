# AIRKEY: submission draft

**Draft only. Nothing has been submitted.** Harshal reads this, fills in the fields marked *Harshal decides*, confirms the final JSON, and sends it himself. The payload goes to `POST https://nearhackathon.com/api/applications` once, and mistakes after that go through https://nearhackathon.com/request-changes. Don't commit the final payload: it contains personal data.

Status words used below: **Done** (in the repo and shown on chain or in tests), **PENDING** (not done yet).

## 1. The fields the API takes

The contract allows exactly these fields, and no others (`website` is a spam trap).

| Field | Rule | Draft value |
|---|---|---|
| `requestId` | UUID, generated once, reused on retries | Generate when sending: `uuidgen \| tr A-Z a-z` |
| `projectName` | 2–80 chars | `AIRKEY` |
| `leadName` | 2–80 chars | `Harshal Bhangale` |
| `email` | valid, max 160 chars | *Harshal decides* (not written here) |
| `size` | `1`, `2 - 4`, `4 - 6`, `6 - 8` or `8+` | `1` (sole author; Harshal confirms) |
| `tracks` | one or more ids | proposed `["security", "agents", "defi"]`; see section 3 |
| `nearAddress` | mainnet payout account, lowercase | *Harshal decides*. It must be a real mainnet account he controls; never invent one. |
| `projectUrl` | public repo URL, unique | `https://github.com/harshalbhangale/near-hack`. **PENDING:** the repo must be public before 2026-11-14T23:59Z. |
| `demoUrl` | public demo post URL | **PENDING:** the X post with the video (section 6) |
| `idea` | 20–2000 chars | section 2 |
| `consent` | `true` only after the notice | Harshal reads: "I agree that the organizers may use these details to review our submission and contact us about this hackathon." |

Other links (not API fields): landing page https://airkey-keyboard.vercel.app · demo video **PENDING** (recording planned 14 Nov 08:00–12:00 UTC).

## 2. `idea` (draft, about 1,700 characters)

> AI agents are getting wallets, and one message can empty them. AIRKEY is a phone keyboard with AI agents in it, and a NEAR contract, Spend Limits, decides what they may spend.
>
> Type "pay harshal 0.2 for dinner" in any chat and hold: the Pay Agent pays. Each agent is its own NEAR sub-account whose only key is a function-call key for Spend Limits. Spend Limits holds the money and decides every payment and swap in a fixed order: Stop everything, blocked list, per-payment and daily limits, an allowed list for untrusted agents, owner approval with Face ID signed on the phone, and per-token trade limits. Every decision is an on-chain event, so a fooled AI still can't move money the contract won't allow.
>
> Whose words drive the agent matters: what you type goes to the trusted Pay Agent, anything you paste goes to the untrusted Inbox Agent. A pasted "send 5 NEAR to drain.near" is blocked on chain. A copied crypto call becomes a trade chip with the token verified on NEAR Intents and a live quote, but only what you type trades.
>
> Follow traders on X: when one posts a call, the Trading Agent trades it for you inside your rules ($1 a call, $3 a day, buy only) and inside its limits on Spend Limits. The Trading Agent swaps on Rhea from Spend Limits, and the tokens come back to it.
>
> The keyboard's own AI (rewrite, reply, translate, Ask) is private AI on NEAR AI Cloud (runs in NEAR's TEE): every answer's signature is verified and its signer is the address NEAR's hardware attests. Every 10 minutes the server checks the Intel TDX quote (with Phala's verifier) and the NVIDIA GPU attestation (with NVIDIA NRAS) against a fresh nonce, plus the compose hash; receipts say verified, partial or failed.
>
> Everything runs on NEAR testnet: real transactions for every step, 41 contract tests, 253 server tests. Spend Limits runs on testnet only; mainnet is next.

## 3. Tracks (proposed)

| Track | Why it fits | See |
|---|---|---|
| `security` (AI Security & Defense) | A contract that limits what AI agents can spend: blocked list, caps, allowed list, approvals, Stop everything; agents hold function-call keys only; pasted text goes to an untrusted agent; address-poisoning warning in the keyboard | `contracts/leash/src/lib.rs`, docs/DEMO.md beats 2 and 7 |
| `agents` (Agent Economy) | Three agents (Pay, Inbox, Trading), each its own NEAR account, spending and trading under owner rules; the Trading Agent trades calls from people you follow, by itself, inside its limits | `server/src/follows.ts`, `server/src/agent.ts` |
| `defi` (Unstoppable DeFi) | Swaps from the keyboard on Rhea held by Spend Limits, token selling back, NEAR Intents for 230 tokens, verification and quotes; limit, stop-loss and take-profit orders | `server/src/rhea.ts`, `server/src/intents.ts`, `server/src/orders.ts` |
| `privacy` (Privacy & Private AI) | Private AI on NEAR AI Cloud (runs in NEAR's TEE), every answer's signature verified; receipts name the model and what was checked | `server/src/ai.ts` |

## 4. What's built in the window, as "do X, see Y"

The repo's first commit is `d8f0da1` on 2026-11-12, inside the hackathon window (announcement 2026-10-19, end 2026-11-14). Code that existed before the hackathon is listed in section 7.

| Do | See |
|---|---|
| `cd contracts/leash && cargo test` | 41 tests pass: one per rule, approvals, reports, the injection case, swaps and token sells, and the same code on a mainnet account |
| `cd server && npm install && npm test` | 253 tests: parser, receiver checks, swaps, quotes, orders, copied calls, following, the Assist panel, GIFs, OutLayer signing, the full command flow |
| Read the last end-to-end run | [`docs/evidence/testnet-e2e.md`](evidence/testnet-e2e.md): 9 of 9 real testnet transactions |
| Type `pay harshal 0.2` in the keyboard and hold | Paid: [8yfavh6V…](https://testnet.nearblocks.io/txns/8yfavh6Ve4Sbyq55XxHjT3ARiU7MGDwVyFpyHoWaviek) |
| Copy a scam asking for 5 NEAR, tap the shield | Blocked by the contract on chain: [HkM96rGV…](https://testnet.nearblocks.io/txns/HkM96rGVBx51xEJyDxmdwsRVhE29W6XFtRZ7zZDEEHN4) |
| Approve a new account in the app with Face ID | The phone signs `approve`: [34yxQfVF…](https://testnet.nearblocks.io/txns/34yxQfVFKN9gytQoNYy74wChike3iMN3BdT63ejd6noJ) |
| Copy "$SOL breaking out, I'm buying", tap the shield, hold Buy | Trade chip in under 1 s; 0.2841 NEAR → 0.597 USDC by Spend Limits on Rhea: [7XUq6MLF…](https://testnet.nearblocks.io/txns/7XUq6MLFCiPL15FynnKsyWp9KCx6Ki7pc2WsgTDqRUey) |
| Follow @CryptoKaleo, trade his latest call | 0.295 NEAR → 0.6197 USDC by the Trading Agent: [5MyPgFPD…](https://testnet.nearblocks.io/txns/5MyPgFPDiaUwR8EttJ9U6eUUAsxQ6c2TeCnvqLV16QNj) |
| Sell USDC back from the swap screen | 0.5 USDC → 0.2365 NEAR: [JE32cE9q…](https://testnet.nearblocks.io/txns/JE32cE9q2rjHMGhJT3P1hgq7YVSfD4xkkNXANmeDA1Q) |
| Hold space, Rewrite | Five versions in 1–2 s from NEAR AI Cloud, signature verified (`docs/screens/ai-rewrite-near.png`) |
| Tap Stop everything | Every agent stops, enforced by the contract (see `docs/DEMO.md`) |
| Follow the click-by-click demo | `docs/DEMO.md` |

## 5. How AIRKEY uses NEAR

| NEAR piece | Used for | See |
|---|---|---|
| A Rust contract on testnet | Spend Limits: holds the money and decides every payment and swap | [`leash.airkey-harshal.testnet`](https://testnet.nearblocks.io/address/leash.airkey-harshal.testnet), `contracts/leash/src/lib.rs` |
| Sub-accounts | One account per agent: `pay.`, `inbox.`, `trader.airkey-harshal.testnet` | `scripts/setup-testnet.mjs`, `scripts/add-trading-agent.mjs` |
| Function-call access keys | Agents can only call Spend Limits' `pay`, `report` (and `swap` for the trader); the protocol refuses anything else | e2e steps 6 and 7 |
| Full-access device key | The owner's approvals and rule changes, signed on the phone after Face ID; the server only relays | `server/src/owner.ts` |
| NEP-297 events | Every decision is readable on chain | `contracts/leash/src/lib.rs` |
| Rhea (on NEAR) | Testnet swaps and sells: Spend Limits wraps NEAR and swaps in one pool; the tokens come back to Spend Limits | `server/src/rhea.ts` |
| NEAR Intents / 1Click | Token list (230 assets), token checks for copied calls, live prices and quotes; the mainnet deposit path is in code | `server/src/intents.ts` |
| NEAR AI Cloud | Private AI on NEAR AI Cloud (runs in NEAR's TEE): every answer's signature is verified and its signer is the address NEAR's hardware attests. Every 10 minutes the server checks the Intel TDX quote (with Phala's verifier) and the NVIDIA GPU attestation (with NVIDIA NRAS) against a fresh nonce, plus the compose hash; receipts say verified, partial or failed. Used for the keyboard's AI and for wording the rules can't read | `server/src/ai.ts`, `server/src/ai-stream.ts` |

**Spend Limits runs on testnet only.** It did not enforce any mainnet swap. Mainnet is next.

## 6. PENDING (not done yet)

| Item | Owner / note |
|---|---|
| Mainnet Spend Limits | Next. Needs a funded mainnet account; all mainnet steps are Harshal's, by hand (`docs/MAINNET-STEPS.md`) |
| Bracket, trailing and TWAP orders | Not built |
| Android build | None. The landing page's Android button downloads the Kall Markets APK as a placeholder; remove it before judging |
| Repo public | Harshal, before 2026-11-14T23:59Z |
| Demo video and the X post | Harshal records (`docs/DEMO.md`, about 2:28) and posts; the post must say it was built at NEAR HACKATHON and tag @NEARProtocol and #NEARHackathon |
| Disclosure of Kall Markets code (section 7) | Harshal confirms the facts before sending; see the note there |

## 7. Disclosures

- **NOTE FOR HARSHAL, decide before sending:** Kall Markets is entered separately in this hackathon by someone else, and its license is "all rights reserved". Code from Kall Markets is in this repo (the keyboard core below, and parts adapted in the window: letter-hold actions, vault shorthand, the GIF tab; the AI panel was rewritten from scratch). Either keep this disclosure exact, or replace that code before submitting.
- **Pre-hackathon code (baseline).** Two of Harshal's earlier projects predate this hackathon, and parts of them were adapted into this repo (README › Disclosures):
  - **Kall Markets** (an AI keyboard): the keyboard core in `ios/AirKeyKeyboard/` (`Layout/`, `Design/`, `Engine/` with the typing engine and dictionary, `Surfaces/`, `Resources/`).
  - **Kall Markets** (a trading keyboard): keyboard haptics, the hold-to-confirm pattern, and the app's visual design.

  Everything NEAR-specific was built in the window: the Spend Limits contract, the agents and their keys, the server, Rhea and NEAR Intents swaps, the keyboard's agent strip (`ios/AirKeyKeyboard/Agent/`), the money-safe typing rules, the vault, and the app.
- No `pre-hackathon` / `hackathon-submission` tags exist: the repo itself started in the window, so all commits are window work, and the baseline above is code that was copied in and named in the README.
- Built with an AI coding assistant (Claude Code). Harshal chose the product, the rules and every trade-off.
- Sole author and owner: Harshal Bhangale.
- License: MIT (`LICENSE`).
