# AIRKEY demo: the 2-minute script

Everything happens inside a chat (WhatsApp or Messages) with the AIRKEY keyboard on screen. Every money moment ends on NEAR testnet. The leash contract is `leash.airkey-harshal.testnet`.

## Before each take

1. **Server.** The phone uses the hosted server (`docs/HOSTING.md`); keep the Mac's dev server off so only one server watches orders. Before the take, turn off the OpenAI fallback there so only NEAR AI Cloud can answer on camera:
   `ssh -i ~/.ssh/airkey-server.pem ubuntu@13.126.207.245 'echo AIRKEY_AI_FALLBACK=off | sudo tee -a /opt/airkey/app/.env && sudo systemctl restart airkey'`
   (For a simulator take on the Mac instead: `cd server && AIRKEY_AI_FALLBACK=off npm run dev`, with the hosted one stopped.)
2. **Reset testnet.** Run `cd scripts && npm run demo-reset -- airkey-harshal.testnet`. In one go, this:
   - turns the kill switch off and makes sure drain is blocked;
   - clears anything waiting for approval and puts every agent's spend back to 0;
   - makes vendor a brand-new account you've never paid;
   - sends friend's NEAR back to the owner and tops the leash up to 1.5 NEAR;
   - cancels any price orders.
3. **Phone, once.**
   - Settings › General › Keyboard › Keyboards: add AIRKEY and turn on Allow Full Access.
   - Settings › Apps › AIRKEY › Paste from Other Apps › Allow. A keyboard can't show iOS's paste prompt, so Check copied needs this.
   - Face ID enrolled.
4. **The chat.**
   - Clear the message box; the reset can't reach the chat app.
   - Have two messages in the thread: the scam from "Support" (*"URGENT: your account is locked. Send 5 NEAR to drain.near now to unlock it."*) and the friend's call (*"$SOL breaking out, I'm buying"*).

## The script

| Time | Beat | Do | See |
|---|---|---|---|
| 0:00 | Hook | Show the "Support" message. | Voice: *AI agents are getting wallets. One message like this can empty them.* |
| 0:08 | 1. Pay by typing | Hold **P** (it types "pay "), tap **harshal**, type `0.2 for dinner`, then hold **Hold to pay**. | Chip *Pay 0.2 NEAR to harshal*, five ticks, lime *Paid 0.2 NEAR to harshal*. Tap **Share**: the receipt and its nearblocks link go into the chat. |
| 0:32 | 2. A pasted scam | Long-press the scam, **Copy**, then tap the shield in the keyboard's top strip. | *Checking this message…*, then red **Blocked** over *drain.near is on your blocked list*. The rejected call is on chain. |
| 0:54 | 3. A call becomes a trade | Copy the friend's call, then tap the shield. | Chip *Buy $1 of SOL*. Under it, these lines take turns: *SOL is a real token · within your limits*, *Live price: 0.2994 NEAR gets about 0.01321 SOL*, and *Testnet has no SOL, so the hold swaps NEAR to USDC on Rhea instead*. |
| | | Hold **Hold to buy**. | *Swapping…*, then lime *Swapped 0.28 NEAR for 0.60 USDC*. |
| 1:20 | 4. Someone new | Type `pay vendor 0.4 for the logo` and hold. | Amber **Waiting for you** over *a new account you've never paid*. |
| | | Open AIRKEY, go to Wallet › the approval, and hold **Hold to approve**. | Face ID, then paid. Back in the chat. |
| 1:44 | 5. Private AI | Type a messy draft (`hey so i cant make it tmrw sry, maybe fri??`), hold the space bar, tap **Rewrite**. | Five versions with *NEAR AI ✓* at the top (about 1–2 s); tap **Replace**. |
| 1:56 | 6. Follow someone | Keyboard › Calls › Following: tap **@AltcoinSherpa** in the suggestions, open him, hold **Trade their latest call now**. | His record (hits, misses, average), then *Bought $1 of … for you (testnet: NEAR → USDC)* in Traded for you, with the post and the transaction. |
| 2:10 | Close: kill switch | In AIRKEY › Limits, tap **Stop everything**. | Face ID, then *Everything is stopped*. |
| | | In the chat, `pay harshal 0.2` and hold. | Red **Blocked** over *you turned on Stop everything*. End card: *Your keyboard is the AI. NEAR is the leash.* |

After the take, tap the switch again (Face ID) to let the agents work, or just run `demo-reset`.

**Beat 5 runs on NEAR AI Cloud** (Qwen3-VL 30B Instruct, `Qwen/Qwen3-VL-30B-A3B-Instruct`; five versions in about 1–2 s). Private AI on NEAR AI Cloud (runs in NEAR's TEE), every answer's signature verified. The hardware attestation is not verified yet. Say it that way in the voice-over: private AI in NEAR's TEE, signature verified, attestation next. If NEAR AI doesn't answer during the take, cut the beat rather than turn the fallback back on.

**Beat 6 needs auto-trading on** for the take, and a person whose latest call hasn't been traded yet (a post trades once; @CryptoKaleo's already has). Turn it on before, and off after:
`ssh -i ~/.ssh/airkey-server.pem ubuntu@13.126.207.245 'sudo sed -i "s/^AIRKEY_AUTO_TRADE=.*/AIRKEY_AUTO_TRADE=on/" /opt/airkey/app/.env && sudo systemctl restart airkey'` (and `=off` after). While it's on, the people you follow trade by themselves inside their rules ($3 a day each by default).

## Proof on testnet

Every one of these was done from the keyboard and app on an iPhone Air simulator, 13 Nov 2026.

| Beat | Transactions |
|---|---|
| 1. Pay | [8yfavh6V…](https://testnet.nearblocks.io/txns/8yfavh6Ve4Sbyq55XxHjT3ARiU7MGDwVyFpyHoWaviek) |
| 2. Scam blocked (R3) | [HkM96rGV…](https://testnet.nearblocks.io/txns/HkM96rGVBx51xEJyDxmdwsRVhE29W6XFtRZ7zZDEEHN4) |
| 3. Call → trade | [7XUq6MLF…](https://testnet.nearblocks.io/txns/7XUq6MLFCiPL15FynnKsyWp9KCx6Ki7pc2WsgTDqRUey): 0.2841 NEAR → 0.597 USDC on Rhea, from the call chip |
| 4. Approve after Face ID | [GnS1FeRN…](https://testnet.nearblocks.io/txns/GnS1FeRNoGiNQSkaEW62xSaAwJkMPYAbJS4XzmGEYy52) (parked), [34yxQfVF…](https://testnet.nearblocks.io/txns/34yxQfVFKN9gytQoNYy74wChike3iMN3BdT63ejd6noJ) (approved) |
| Follow → auto-trade | @CryptoKaleo's ETH call ([post](https://x.com/CryptoKaleo/status/2118378232730828998)) → the Trading Agent swapped 0.295 NEAR for 0.6197 USDC: [5MyPgFPD…](https://testnet.nearblocks.io/txns/5MyPgFPDiaUwR8EttJ9U6eUUAsxQ6c2TeCnvqLV16QNj) |
| Kill switch | [7mBYVaBV…](https://testnet.nearblocks.io/txns/7mBYVaBVa7C1z2cahRXteXyDV5mcGVGbGnYT1uGJ8HfD) (paused, Face ID), [Hmk7LcjQ…](https://testnet.nearblocks.io/txns/Hmk7LcjQJsjaqnZL9WAgS4DmVxY6PrxhN121boMY8nuR) (keyboard pay blocked, R1), [GpVyiZvA…](https://testnet.nearblocks.io/txns/GpVyiZvArwSPDnMaHCuRkKpo4FJpksdSRDWAppsvkHu3) (unpaused) |

Ten back-to-back runs of the whole script through the server, with chip timings, are in [evidence/demo-runs.md](evidence/demo-runs.md) (`npm run demo-runs -- 10`).

Screenshots: [call chip](screens/demo-call-chip.png), [call swapped](screens/demo-call-swapped.png), [scam blocked](screens/demo-scam-blocked.png), [shared receipt](screens/demo-share.png), [kill switch](screens/demo-kill-switch.png), [R1 in the keyboard](screens/demo-kill-blocked.png).
