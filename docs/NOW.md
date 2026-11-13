# AIRKEY: where it stands and the next hour

One line each. Updated 13 Nov 2026.

## Done
- [x] Typing from Glyf in the keyboard: autocorrect, suggestions, swipe, space-bar cursor, emoji, clipboard, themes, games
- [x] Money in the keyboard: "pay harshal 0.2" → hold → paid on testnet, Share puts the receipt in the chat
- [x] A pasted scam is blocked on chain; a new person waits for your Face ID; the kill switch stops every agent
- [x] Swap NEAR → USDC/USDT on Rhea (testnet), from the keyboard and the app
- [x] Copied crypto call → a trade chip with token check and limits
- [x] Hold space for AI: rewrite, reply, translate, tone, on NEAR AI Cloud (DeepSeek V4.1 Flash, ~3 s, signature verified); OpenAI only as fallback
- [x] Contract can sell tokens it holds (USDC/USDT → NEAR, USDC ↔ USDT): proven on a test copy, 38 contract tests
- [x] 192 server tests; demo script, reset command and evidence docs
- [x] App installed on your iPhone 16 Pro Max
- [x] Mainnet steps written for you to do by hand (docs/MAINNET-STEPS.md)

## Problems found
- [x] Full swap screen: You pay / You get, rate, minimum, fee, route, limits; orders (limit, stop-loss, take-profit, bracket, trailing, TWAP)
- [x] Plain wording on every screen (Plain.swift); details one tap away
- [x] Haptic scheme in the keyboard (needs a feel-check on the phone)
- [ ] Your phone can't reach the server on the Mac over its own hotspot
- [ ] Free Apple signing: the app and keyboard can't share settings on your phone, so vault and contacts added in the app don't reach the keyboard, and the install expires in 7 days
- [x] NEAR AI key in keys/near-ai.key. GLM-5.1 took ~43 s (past the 20 s timeout), so server/.env sets NEAR_AI_MODEL=deepseek-ai/DeepSeek-V4.1-Flash-1017
- [x] Live leash upgraded with token selling; sold 0.5 USDC for NEAR from the swap screen (docs/evidence/token-swaps.md)
- [ ] The dev server stops whenever the session restarts
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
- [ ] **Phone ↔ Mac**: put both on the same Wi-Fi (not the phone's hotspot), or say OK to a temporary public link to the server
- [x] Search key (Serper, in server/.env)
- [x] GIF key (Klipy, in server/.env as KLIPY_API_KEY; GIFs not built yet)
- [ ] Optional: a paid Apple Developer account ($99/year) removes the 7-day expiry and lets the keyboard share settings with the app

## The next hour
| Time | What | Who |
|---|---|---|
| 0:00–0:40 | Swap screen and orders finished and checked on the simulator | builder 1 |
| 0:00–0:40 | Wallet + Calls finished and checked | builder 3 |
| 0:00–0:50 | Glyf AI features ported (search waits on a key) | builder 4 |
| 0:00–0:40 | Plain wording + haptics across keyboard and app | builder 5 |
| 0:40–0:55 | Merge each as it lands, run all tests, click through the demo, push | me |
| 0:55–1:00 | Upgrade the real contract, build for your phone, report with screenshots | me |

Glyf extras (GIFs, voice, calendar, temp mail, tour) and the Pay screen come right after, in the next hour.
