# Gap list: Keybots's core journey (14 Nov 2026, 08:15 UTC)

The journey: **see a KOL call → review the trade → hold to confirm → NEAR enforces the agent's limits → see a verifiable receipt.**

Kall Markets is compared only from its public README (no code read).

## What already works in Keybots
- Copied crypto call → a trade chip in under 1 s: token checked on NEAR Intents, a live quote, and the Trading Agent's limits read from chain (`server/src/calls.ts`).
- The leash contract decides every swap: Stop everything, blocked list, per-trade and daily limits; a refusal is an on-chain `blocked` event (`contracts/leash/src/lib.rs`, `swap`). 38 contract tests.
- Real testnet swaps on Rhea from the leash, the tokens come back to it (tx 7XUq6MLF…, 5MyPgFPD…).
- Private AI on NEAR AI Cloud: each answer's signature checked, the signer matched to the attested enclave, and every 10 minutes the TDX quote (Phala) and GPU (NVIDIA NRAS) are checked (`server/src/attest.ts`).
- Kall's call feed and caller records (`server/src/kall.ts`), a public leash page (`/leash`), a keyless dry run (`npm run try`).

## What Kall Markets does better (from its README)
- A trade panel that shows what you pay, what you get and how long it takes, in one card, before you sign.
- Guard: warnings shown before signing (lookalike address, unknown account, wrong chain, new recipient, daily limit).
- Mainnet swaps across many chains from the person's own wallet.
- A privacy receipt the person can open per answer.

## The gaps in Keybots's journey, and the smallest fixes
1. **No source on the call.** The chip says "Buy $1 of SOL" but not who posted it, when, or a link to the post. → One compact KOL card: author, time, link, the original text, the caller's record; "Review trade" (no trade on sight).
2. **The quote isn't a full review.** No minimum received, slippage, venue/pool or where the funds sit; the testnet stand-in is a rotating line. → One review card: pay, receive, minimum, slippage, network, venue, where funds sit, the stand-in stated before the hold.
3. **Quotes don't expire and a confirm can run twice.** → A review id that expires after 30 s; confirm is idempotent per review (a second confirm returns the first receipt, never a second trade).
4. **An over-limit swap is refused by the server, not the contract.** The contract would refuse it, but it never sees it. → Send it to the contract so the refusal is an on-chain event with a transaction link; say "refused by the contract" vs "refused by the server" in the receipt.
5. **The hold has no cancel or accessible alternative**, and states (loading, blocked, failed) are thin. → Visible progress, release to cancel, a VoiceOver action, clear state lines.
6. **The privacy receipt lists checks but not what is still trusted.** → Show each check as passed / failed / unavailable, and the trust assumptions (remote verifiers, shared signing key, no TLS binding, retention not verified).
7. **Limits are buried.** → One sentence on the review card: "The Trading Agent can spend up to 1 NEAR a trade and 2 NEAR a day. You can stop it."

## Not changed
- Auto-trading stays off on the server (`AIRKEY_AUTO_TRADE` unset): the demo trade is confirmed by hand.
- Typed-versus-pasted is decided by the keyboard and server (the trusted client/server boundary), not by the contract.
