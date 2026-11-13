# AIRKEY: where it stands and the next hour

One line each. Updated 13 Nov 2026.

## Done
- [x] Typing from Glyf in the keyboard: autocorrect, suggestions, swipe, space-bar cursor, emoji, clipboard, themes, games
- [x] Money in the keyboard: "pay harshal 0.2" → hold → paid on testnet, Share puts the receipt in the chat
- [x] A pasted scam is blocked on chain; a new person waits for your Face ID; the kill switch stops every agent
- [x] Swap NEAR → USDC/USDT on Rhea (testnet), from the keyboard and the app
- [x] Copied crypto call → a trade chip with token check and limits
- [x] Hold space for AI: rewrite, reply, translate, tone (NEAR AI first, OpenAI fallback)
- [x] Contract can sell tokens it holds (USDC/USDT → NEAR, USDC ↔ USDT): proven on a test copy, 38 contract tests
- [x] 130 server tests; demo script, reset command and evidence docs
- [x] App installed on your iPhone 16 Pro Max
- [x] Mainnet steps written for you to do by hand (docs/MAINNET-STEPS.md)

## Problems found
- [ ] A swap is a one-line chip: no price, fee or minimum shown → being replaced by a full swap screen (builder 1)
- [ ] Jargon on screen: "leash", "R3", "Inbox Agent", "Trading Agent is on it…" mean nothing to a new user → plain wording pass (builder 5)
- [ ] Haptics are basic → a full haptic pass, better than Apple's keyboard (builder 5)
- [ ] Your phone can't reach the server on the Mac over its own hotspot
- [ ] Free Apple signing: the app and keyboard can't share settings on your phone, so vault and contacts added in the app don't reach the keyboard, and the install expires in 7 days
- [ ] No NEAR AI key: AI answers come from OpenAI, so the "private AI" claim isn't true yet
- [ ] Your real contract isn't upgraded with token selling yet (waiting on the swap screen, then one careful upgrade)
- [ ] The dev server stops whenever the session restarts
- [ ] Three of ten test runs failed on the network ("fetch failed"); the call chip was over 2 s twice
- [ ] The paste guard (warning on a pasted unknown address) is built but not checked on screen
- [ ] Glyf's letter-hold actions, vault shorthand and smart chips: landed earlier, never fully checked

## In progress
- [~] Full swap screen like Glyf: You pay / You get, picker, rate, minimum, fee, route, limits, Hold to swap; limit / stop-loss / take-profit / bracket / trailing / TWAP orders (builder 1)
- [~] Wallet section like Kall: balances, agents, activity, orders, Pay someone; Calls section: copied calls and their trades (builder 3)
- [~] All of Glyf's AI: search, live translate while typing, Act (streamed rewrites), Ask, smart suggestion chip, copied-text actions, My glyfs and Build your own (builder 4)
- [~] Plain wording everywhere, and great haptics (builder 5)

## To do after that
- [ ] Merge each builder, test, click through the demo by hand, push
- [ ] Upgrade the real contract with token selling, then check it's unpaused and the balance is right
- [ ] Pay screen like Glyf's (PaySurface)
- [ ] Glyf extras: GIFs and stickers, voice through the app, calendar booking, temp mail, first-run tour, weather
- [ ] Install the new build on your phone
- [ ] README, STATUS and video captions match what's real; record the demo (freeze 14 Nov 14:00 UTC)

## Needed from you (blockers)
- [ ] **NEAR AI Cloud API key**, so the AI is private and signed (put it in `server/.env` as `NEAR_AI_API_KEY=…`, or send it to me)
- [ ] **Phone ↔ Mac**: put both on the same Wi-Fi (not the phone's hotspot), or say OK to a temporary public link to the server
- [ ] **Search key**: Glyf's search uses Brave Search or Serper. OK to reuse Glyf's key from its own `.env`, or give a new one?
- [ ] **GIF key**: Glyf's GIFs use Klipy. Same question.
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
