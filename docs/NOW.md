# AIRKEY: where it stands and the next hour

One line each. Updated 14 Nov 2026, 05:15 UTC.

## Done
- [x] Typing from Glyf in the keyboard: autocorrect, suggestions, swipe, space-bar cursor, emoji, clipboard, themes, games
- [x] Money in the keyboard: "pay harshal 0.2" → hold → paid on testnet, Share puts the receipt in the chat
- [x] A pasted scam is blocked on chain; a new person waits for your Face ID; the kill switch stops every agent
- [x] Swap NEAR → USDC/USDT on Rhea (testnet), from the keyboard and the app
- [x] Copied crypto call → a trade chip with token check and limits
- [x] Hold space for AI: rewrite, reply, translate, tone, on NEAR AI Cloud (DeepSeek V4.1 Flash, ~3 s, signature verified); OpenAI only as fallback
- [x] Contract can sell tokens it holds (USDC/USDT → NEAR, USDC ↔ USDT): proven on a test copy, 38 contract tests
- [x] 196 server tests; demo script, reset command and evidence docs
- [x] Server hosted on Lightsail with HTTPS and a token (docs/HOSTING.md); the phone build talks to it, so no same-Wi-Fi or tunnel needed
- [x] Vault saved on the server so the keyboard sees what the app saves, even with free signing
- [x] YouTube search from the keyboard
- [x] App installed on your iPhone 16 Pro Max
- [x] Mainnet steps written for you to do by hand (docs/MAINNET-STEPS.md)

## Problems found
- [x] Full swap screen: You pay / You get, rate, minimum, fee, route, limits; orders (limit, stop-loss, take-profit, bracket, trailing, TWAP)
- [x] Plain wording on every screen (Plain.swift); details one tap away
- [x] Haptic scheme in the keyboard (needs a feel-check on the phone)
- [x] Phone can't reach the Mac: fixed by the hosted server
- [ ] Free Apple signing: the install expires in 7 days (vault now goes through the server; contacts added in the app still don't reach the keyboard)
- [x] NEAR AI answers (rewrite, reply) with the signature verified, 2–4 s warm. The old default name (GLM-5.1) is now an alias that NEAR AI refuses with no-aliasing, which made answers fall back to OpenAI; default is now deepseek/deepseek-v4.1-flash
- [x] Live leash upgraded with token selling; sold 0.5 USDC for NEAR from the swap screen (docs/evidence/token-swaps.md)
- [x] The dev server stops whenever the session restarts: the hosted one runs under systemd
- [ ] Three of ten test runs failed on the network ("fetch failed"); the call chip was over 2 s twice
- [ ] The paste guard (warning on a pasted unknown address) is built but not checked on screen
- [ ] Glyf's letter-hold actions, vault shorthand and smart chips: landed earlier, never fully checked

## Also landed
- [x] Wallet like Kall, and a Calls section, in the keyboard
- [x] All of Glyf's AI: streamed rewrite versions, Ask, live translate, suggestion chip, copied-text actions, search (Serper), My glyfs, Build your own; copied money text never goes to an AI action
- [x] Everything merged to main (= ux-glass); old demo kept under tag `demo-ready`

## To do after that
- [ ] Pay screen like Glyf's (PaySurface)
- [ ] Glyf extras: GIFs and stickers, voice through the app, calendar booking, temp mail, first-run tour, weather
- [ ] Install the new build on your phone
- [ ] README, STATUS and video captions match what's real; record the demo (freeze 14 Nov 14:00 UTC)

## Needed from you (blockers)
- [x] NEAR AI Cloud API key
- [x] Phone ↔ server: hosted
- [x] Search key (Serper, in server/.env)
- [x] GIF key (Klipy, in server/.env as KLIPY_API_KEY; GIFs not built yet)
- [ ] Optional: a paid Apple Developer account ($99/year) removes the 7-day expiry and lets the keyboard share settings with the app

## Until submission (14 Nov, UTC)
| Time | What |
|---|---|
| now–07:00 | Click through every demo beat on the simulator against the hosted server; fix any wording that doesn't match DEMO.md |
| 07:00–09:00 | Build and install on your iPhone (hosted server baked in); check haptics, paste guard, letter-hold actions on the phone |
| 09:00–13:00 | Pay screen like Glyf's, then Glyf extras in order: GIFs, first-run tour; stop at 13:00 whatever is left |
| 13:00–14:00 | Full tests, demo-reset (asks you first: it's on-chain), README/STATUS final, push. Feature freeze 14:00 |
| 14:00–17:00 | Record the demo (you), I cut it with landing/video/make.sh |
| 17:00–21:00 | Submission text, links, evidence; submit well before 23:59 |
