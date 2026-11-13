# Mainnet: steps Harshal does by hand

AIRKEY's code and its builders never sign or send anything on mainnet. The leash contract runs on testnet only. The server's mainnet path is off unless `NEAR_NETWORK=mainnet`, and even then it refuses any swap above $0.15 (`AIRKEY_MAINNET_USD_CAP`).

## The one optional mainnet swap: about $0.10 of NEAR to SOL through NEAR Intents

It proves that NEAR Intents' live quotes, which the keyboard shows, are real and fill.

**Checked on 13 Nov 2026 with a free dry quote** from NEAR Intents' 1Click API: 0.0284 NEAR (≈ $0.099) → 0.00122 SOL (≈ $0.098), settling in about 22 seconds. The minimum is fine at this size.

### What you need
- About **0.04 NEAR** in your own NEAR wallet: 0.0284 for the swap, plus a little for gas and token storage. Total ≈ $0.14.
- Nothing else. Don't fund any AIRKEY account for this.

### Steps
1. Open **https://app.near-intents.org** and connect your own NEAR wallet.
2. Swap **from NEAR** **to SOL**, amount **0.0284 NEAR**.
3. Check the quote. It should be close to **0.0012 SOL**. If it shows much less, stop.
4. Keep the SOL in your NEAR Intents balance. If you'd rather receive it on Solana, enter a Solana address you own.
5. Confirm in your wallet. It asks you to sign one or two transactions (wrapping NEAR and the deposit).

### What you should see
- The swap shows as **Success** in the NEAR Intents app within about a minute.
- On **nearblocks.io**, your account shows a transfer to the deposit address.
- 0.0012 SOL appears in your NEAR Intents balance, or in your Solana wallet if you gave one.

### Then
Send me the nearblocks link for your transaction and the NEAR Intents status link. I'll add one line to the README and to `docs/evidence/mainnet.md`:

> On mainnet, one real NEAR Intents swap (≈ $0.10 of NEAR to SOL) was made by hand; the leash contract runs on testnet only.

If you skip this, the README says AIRKEY is testnet only, and that's fine.
