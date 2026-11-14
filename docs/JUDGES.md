# AIRKEY for judges

**One journey:** see a KOL call → review the trade → hold to confirm → the NEAR contract (the leash) enforces the agent's limits → a receipt you can check on chain.

Everything runs on **NEAR testnet**. Nothing here touches mainnet or real money.

## Try it without a phone or keys

Needs Node 20+.

```bash
git clone https://github.com/harshalbhangale/near-hack && cd near-hack/server && npm install
```

| Do | See |
|---|---|
| `npm run try -- --call` | The newest call from Kall's feed, reviewed as the keyboard shows it: author, link, the post, what you'd pay and get on Rhea (testnet), the minimum after 1% slippage, where the funds sit, the stand-in if the post names a coin testnet doesn't have, and the Trading Agent's limits read live from the contract. **Dry: nothing is sent.** |
| `npm run try -- "pay harshal 0.2 for dinner"` | Would pay: within the Pay Agent's 0.5 NEAR per-payment limit, read from chain. |
| `npm run try -- "pay drain 5" --pasted` | Would be blocked: drain is on the contract's blocked list. |
| `npm run try -- "pay vendor 0.4 for the logo" --pasted` | Would wait for the owner's Face ID: the untrusted Inbox Agent can only pay allowed accounts. |
| Open [the live leash page](https://13-126-207-245.sslip.io/leash) | The contract right now: NEAR held, Stop everything, each agent's limits and today's spend, the blocked and allowed lists, recent decisions with transaction links. |
| `cd contracts/leash && cargo test` | 38 tests: one per rule, approvals, swaps, token sells. |
| `cd server && npm test` | 253 tests (fake chain and network; 12 OutLayer tests need a local port). |

## Real vs. simulated

| Part | Real | Simulated or limited |
|---|---|---|
| KOL calls | Kall's feed (calls Kall tracks from the people it follows) | Not every post on X. If Kall doesn't answer, three posts labelled **Sample post** are shown instead. |
| Reading the call | Fixed rules on the server | No AI reads the call. |
| The trade | A real Rhea swap on NEAR testnet, from the leash, through the Trading Agent | Testnet has no SOL/BTC/ETH: the trade swaps NEAR to USDC, and the review and receipt say so before and after. |
| NEAR Intents | Token checks and prices | No testnet. Any Intents quote is labelled a dry mainnet quote: no funds move. |
| Limits | Enforced by the leash contract on chain (per trade, per day, Stop everything) | Typed-vs-pasted (which agent acts) is decided by the keyboard and server, the trusted client/server boundary, not by the contract. |
| Private AI | NEAR AI Cloud (Qwen3-VL 30B, in NEAR's TEE): signature verified, signer matched to the attested enclave, TDX quote and GPU attestation checked every 10 minutes | The TDX and GPU verdicts come from Phala's and NVIDIA's verifiers, not checked on the phone; a model's instances share one signing key; the connection isn't bound to the attested machine; NEAR AI's data retention isn't verified by AIRKEY. |
| Auto-trading | Built (`server/src/follows.ts`) | **Off** in the demo and on the hosted server: every trade is confirmed by hand. |

## Evidence on testnet

| What | Transaction |
|---|---|
| A paid payment from the keyboard | [8yfavh6V…](https://testnet.nearblocks.io/txns/8yfavh6Ve4Sbyq55XxHjT3ARiU7MGDwVyFpyHoWaviek) |
| Over the per-payment limit: **refused by the contract** (event `blocked`, rule R4) | [8FXGiFHR…](https://testnet.nearblocks.io/txns/8FXGiFHRU6bVjTbyuz9B4HomyJn1ufoxtE9Q7C3NbyfX) |
| A pasted scam to a blocked account: refused by the contract | [HkM96rGV…](https://testnet.nearblocks.io/txns/HkM96rGVBx51xEJyDxmdwsRVhE29W6XFtRZ7zZDEEHN4) |
| A copied call traded on Rhea from the leash | [7XUq6MLF…](https://testnet.nearblocks.io/txns/7XUq6MLFCiPL15FynnKsyWp9KCx6Ki7pc2WsgTDqRUey) |
| A followed trader's call traded by the Trading Agent | [5MyPgFPD…](https://testnet.nearblocks.io/txns/5MyPgFPDiaUwR8EttJ9U6eUUAsxQ6c2TeCnvqLV16QNj) |
| The owner's approval, signed on the phone with Face ID | [34yxQfVF…](https://testnet.nearblocks.io/txns/34yxQfVFKN9gytQoNYy74wChike3iMN3BdT63ejd6noJ) |
| Stop everything (paused, then a payment refused) | [7mBYVaBV…](https://testnet.nearblocks.io/txns/7mBYVaBVa7C1z2cahRXteXyDV5mcGVGbGnYT1uGJ8HfD), [Hmk7LcjQ…](https://testnet.nearblocks.io/txns/Hmk7LcjQJsjaqnZL9WAgS4DmVxY6PrxhN121boMY8nuR) |

## Tracks

| Track | Evidence |
|---|---|
| **AI Security & Defense** | The leash contract limits what AI agents can spend and records every refusal on chain; agents hold function-call keys only; pasted text goes to an untrusted agent; a pasted unknown address gets a warning. Limits: not every scam or prompt injection is stopped; typed-vs-pasted relies on the client/server boundary. |
| **Unstoppable DeFi** | A KOL call becomes a reviewed Rhea swap from the leash: quote, minimum, slippage, 30-second expiry, one trade per confirmation, the actual result and its transaction. |
| **Privacy & Private AI** | Private AI on NEAR AI Cloud: every answer's receipt names the provider and shows each check (signature, signer, TDX quote, GPU, nonce, compose hash) as passed, failed or unavailable, plus what is still trusted. Only the text the person chooses is sent; money text is never sent. |
| **Open Innovation** | Agents with their own NEAR accounts, held to on-chain limits, inside the keyboard people already type in. |

## Not done

- Mainnet: the leash runs on testnet only. Mainnet is next.
- Only one chain: no cross-chain swaps from the person's own wallet.
- No Android build.
