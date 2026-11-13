# AIRKEY: done and to do

One line each. `[x]` done, `[ ]` to do, `[~]` in progress. Deadline: 14 Nov 2026, 23:59 UTC.

## Keyboard: typing and feel
- [~] Kall Markets' keyboard core moved into AIRKEY (keys, layouts, accent popups, delete repeat)
- [~] Glide (swipe) typing with a trail
- [~] Kall Markets' typing engine: autocorrect, 3 suggestions, next-word prediction, learning
- [~] Space-bar cursor glide
- [~] Toolbar strip and menu
- [~] Clipboard history panel and paste chip
- [~] Emoji board, emoji next to words
- [~] Themes: glass keys, light and dark from the chat app
- [x] Autocorrect never touches names, NEAR accounts, token symbols, $tickers or numbers
- [x] After "pay" or "to", suggest contacts
- [x] One backspace undoes an autocorrection and learns the word
- [x] Space on the number layer goes back to letters
- [x] Haptics on every key like Kall: letter, space, delete, shift, layer, trade, success, error
- [ ] Key sounds, number row and one-handed mode as settings
- [ ] Tested end to end in Messages, light and dark, on AIRKEY's own keys

## Keyboard: money
- [x] Read "pay harshal 0.2" and show a chip
- [x] Hold to pay, swap, buy, sell or place; a tap never runs anything
- [x] Result chip in lime, amber or red, with Share
- [x] Check copied: someone else's message goes to the untrusted Inbox Agent
- [x] Price chips: `$near` shows the live price, with Buy
- [x] Currency conversion, sums and bill splits on the phone
- [x] Vault: your NEAR account and saved addresses in one tap; keys and phrases refused
- [x] Server reads swaps in dollars ("swap $5 of near to usdc", "5$")
- [x] Keyboard reads swaps in dollars too
- [x] Any wording works: AI reader reads what the rules miss; the hold sends its exact command
- [ ] Uniswap-style swap panel in the keyboard, after Kall's trade tab: pay side and get side, chain and token pickers, amount with MAX and presets, live quote, price impact, review card, hold to swap, haptics
- [ ] Balances the leash holds, shown in the keyboard
- [ ] Hold space for AI: rewrite, reply, ask
- [ ] Translate and tone rewrites

## Swaps and trading
- [x] Leash contract `swap`: same rules and caps as `pay`, wraps NEAR, swaps on Rhea, the token comes back to the leash
- [x] Real swaps on testnet: NEAR to USDT and USDC on Rhea (3 on chain)
- [x] Trading Agent `trader.<you>`: its own caps (1 NEAR a trade, 2 a day), key limited to pay, report and swap
- [x] Token checks against NEAR Intents' list (230 assets)
- [x] NEAR Intents quotes for every listed token
- [x] Mainnet path in code: live 1Click quote, leash funds the deposit address, follow the status
- [x] Price-triggered orders with a 15-second watcher and Cancel
- [x] Pasted text can never trade
- [ ] Sell tokens the leash holds back to NEAR
- [ ] Buy NEAR with USDC for real (today it's a quote)
- [ ] More testnet pairs on Rhea
- [ ] Mainnet swaps live (needs a funded mainnet leash, and your go-ahead)
- [ ] Share a trade to the chat as a link
- [ ] Recurring buys (DCA)
- [ ] Tokenized stocks: blocked, Ondo stocks aren't in the public NEAR Intents list

## AI and NEAR private compute
- [x] NEAR AI Cloud reader with signature checks, in code
- [x] OpenAI key saved on this Mac, outside git
- [x] OpenAI as the AI reader until NEAR AI is on (gpt-4.1-mini)
- [ ] NEAR AI Cloud private inference on (needs your NEAR AI Cloud key)
- [ ] Attestation check of the TEE, not just the signature
- [ ] AI receipts: which model, signature, verified or not

## App
- [x] Kall-style design: masthead, cards, big lime numbers, uppercase buttons, badges
- [x] Wallet: NEAR and token balances, leash address, approvals, swap card with hold to swap, recent
- [x] Activity: every command with its receipt and badge
- [x] Leash: kill switch, agents and caps, allow and block lists, signed after Face ID
- [x] Keyboard tab: setup steps and what it does
- [x] Hold to approve, then Face ID
- [ ] Vault editor polish, AI receipts view

## Leash and server
- [x] Leash rules R0 to R7 on testnet, 21 contract tests
- [x] Agents: Payment (trusted), Inbox (untrusted), Trading
- [x] Receiver checks: exists, blocked, allowlisted, account age, paid before
- [x] Receipts for every command; server logs which client sent it
- [x] 80 server tests
- [ ] Host the server (pick Vercel, AWS or Railway)

## More from Kall Markets
- [ ] Vault shorthand and notes in the keyboard
- [ ] Fancy text styles
- [ ] More smart chips: units, time zones, parcel tracking, clean links
- [ ] Search in the keyboard
- [ ] GIFs and stickers (needs a GIF API key)
- [ ] Calendar and temp mail
- [ ] Voice through the app
- [ ] Games

## Kall Markets and partners
- [ ] Follow KOLs and auto-trade their calls within the leash (demo list)
- [ ] Sputnik DAO as a team leash
- [ ] OutLayer TEE agent

## Ship
- [x] Sole owner Harshal; history rewritten, no other names
- [x] README with live transactions and test counts
- [ ] Fresh clone of main builds (waits on the keyboard helper's commits)
- [ ] Demo video
- [ ] NEAR Builders directory profile for hellbuddy.near (later; paste the API key again then, it's never saved)
- [ ] Submit before 14 Nov, 23:59 UTC
