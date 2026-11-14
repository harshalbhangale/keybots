# AIRKEY: where it stands

Updated 14 Nov 2026, 05:35 UTC. Checked on the simulator against the hosted server, and installed on your iPhone.

## Done
- [x] Glyf typing in the keyboard: autocorrect, swipe, cursor, emoji, clipboard, themes. Looks like the iPhone keyboard: blank space bar, icon top-left, lime dots on P/S/C/V
- [x] Pay by typing, then Share. Scam blocked on chain. New person waits for Face ID. Kill switch
- [x] Swap screen like Uniswap: You pay / You get, token picker, rate, minimum, fee, route, limits
- [x] Swap NEAR → USDC/USDT, and sell USDC/USDT back, on testnet (live contract upgraded; 38 contract tests)
- [x] Orders: limit, stop-loss, take-profit
- [x] A copied crypto call becomes a trade chip: "Buy $1 of SOL", real token, live price, within your limits (0.7–0.9 s); it goes away when you start typing
- [x] Wallet like Kall, and a Calls section, in the keyboard
- [x] Hold space for AI, all of Glyf's: rewrite (five versions), reply, translate, tone, Ask, live translate, search, My glyfs. Private on NEAR AI Cloud (Qwen3-VL 30B in NEAR's TEE, signature checked): rewrite in 1–2 s
- [x] Copied money text never goes to an AI action
- [x] Paste warning: a pasted address that isn't yours or a contact's gets "Check every character" (checked on screen)
- [x] Letter hold: hold P types "pay " and shows your contacts (checked on screen)
- [x] Plain words on every screen ("Blocked: drain.near is on your blocked list"; the tab is Limits)
- [x] Haptic scheme (needs your feel-check on the phone)
- [x] Server hosted with HTTPS (docs/HOSTING.md): the phone works on any network
- [x] 196 server tests, 38 contract tests

## Not done
- [ ] Bracket, trailing and TWAP orders
- [ ] Pay screen like Glyf's; GIFs, voice, calendar, temp mail, first-run tour
- [ ] Free Apple signing: the install expires in 7 days; contacts added in the app don't reach the keyboard (vault does, through the server)
- [ ] Mainnet: written for you to do by hand (docs/MAINNET-STEPS.md); the leash runs on testnet only

## Before recording (needs your OK: these send testnet transactions)
1. `npm run demo-reset` in scripts/: unpause, clear the waiting 0.01 NEAR payment, reset spend, top the leash up to 1.5 NEAR (it holds 0.49 now)
2. Turn off the OpenAI fallback on the hosted server (command in docs/DEMO.md)
3. Record docs/DEMO.md, beats 1–5 and the kill switch (about 2:14)
