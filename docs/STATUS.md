# AIRKEY: done and to do

One line each. `[x]` done, `[ ]` to do, `[~]` in progress. Deadline: 14 Nov 2026, 23:59 UTC.

## P0: the demo path (each step proven on chain, script in docs/DEMO.md)
- [x] Typed "pay harshal 0.2" is paid ([8yfavh6V…](https://testnet.nearblocks.io/txns/8yfavh6Ve4Sbyq55XxHjT3ARiU7MGDwVyFpyHoWaviek))
- [x] A pasted scam is blocked ([HkM96rGV…](https://testnet.nearblocks.io/txns/HkM96rGVBx51xEJyDxmdwsRVhE29W6XFtRZ7zZDEEHN4))
- [x] An unknown receiver gets Approve, then Face ID, then paid ([34yxQfVF…](https://testnet.nearblocks.io/txns/34yxQfVFKN9gytQoNYy74wChike3iMN3BdT63ejd6noJ))
- [x] "swap 1 near to usdc" goes through Rhea on testnet ([4gMJo7Aw…](https://testnet.nearblocks.io/txns/4gMJo7Awi9jyb3iVo3981gJJt5Buy5A1jUTyrf8VZ9MS))
- [x] A `$near` price chip
- [x] Share puts the receipt in the chat
- [x] docs/DEMO.md: the click-by-click script with tx links

## Keyboard: typing and feel
- [x] Kall Markets' keyboard core moved into AIRKEY: keys, layouts, accent popups, delete repeat
- [x] Kall Markets' typing engine: autocorrect, 3 suggestions, next-word prediction, learning
- [x] Glide (swipe) typing with a trail, checked in Messages; token tickers (usdc, usdt…) glide too
- [~] Space-bar cursor glide (ported, not checked yet)
- [x] Toolbar strip: the mark and three tools; the rest in the menu
- [~] Clipboard history panel and paste chip (ported, not checked yet)
- [~] Emoji board, emoji next to words (ported, not checked yet)
- [~] Themes: glass keys, light and dark from the chat app (light checked, dark not yet)
- [x] Autocorrect never touches names, NEAR accounts, token symbols, $tickers or numbers
- [x] After "pay" or "to", suggest contacts
- [x] One backspace undoes an autocorrection and learns the word
- [x] Space on the number layer goes back to letters
- [x] Haptics on every key like Kall: letter, space, delete, shift, layer, trade, success, error
- [ ] Types smoothly in Messages, light and dark, checked end to end

## Keyboard: money
- [x] Read "pay harshal 0.2" and show a chip
- [x] Hold to pay, swap, buy, sell or place; a tap never runs anything
- [x] Result chip in lime, amber or red, with Share
- [x] Check copied: someone else's message goes to the untrusted Inbox Agent
- [x] Price chips: `$near` shows the live price, with Buy
- [x] Currency conversion, sums and bill splits on the phone
- [x] Vault: your NEAR account and saved addresses in one tap; keys and phrases refused
- [x] Check copied needs Settings › Apps › AIRKEY › Paste from Other Apps › Allow (a keyboard can't show the paste prompt); the keyboard says so
- [x] Swaps in dollars, in the keyboard and on the server ("swap $5 of near to usdc", "5$")
- [x] Any wording works: an AI reads what the rules miss; the hold sends its exact command
- [ ] A copied crypto call becomes a prefilled trade chip, with token check and leash caps (Kall)
- [ ] Paste guard: a pasted address that isn't a contact or in the vault gets a warning (Kall Markets)
- [ ] Uniswap-style swap panel in the keyboard, after Kall's trade tab (waiting on Harshal: keyboard or app only)
- [ ] Balances the leash holds, shown in the keyboard

## Swaps and trading
- [x] Leash contract `swap`: same rules and caps as `pay`, wraps NEAR, swaps on Rhea, the token comes back to the leash
- [x] Real swaps on testnet: NEAR to USDT and USDC on Rhea (3 on chain)
- [x] Trading Agent `trader.<you>`: its own caps (1 NEAR a trade, 2 a day), key limited to pay, report and swap
- [x] Token checks against NEAR Intents' list (230 assets)
- [x] NEAR Intents quotes for every listed token
- [x] Mainnet path in code: live 1Click quote, leash funds the deposit address, follow the status
- [x] Price-triggered orders with a 15-second watcher and Cancel
- [x] Pasted text can never trade on its own
- [ ] One small mainnet NEAR Intents swap as proof (only after Harshal funds a mainnet leash and says go)
- [ ] Sell tokens the leash holds back to NEAR
- [ ] Buy NEAR with USDC for real (today it's a quote)

## AI and NEAR private compute
- [x] NEAR AI Cloud reader with signature checks, in code
- [x] OpenAI key saved on this Mac, outside git
- [x] NEAR AI Cloud by default, OpenAI as the fallback when NEAR AI has no key or doesn't answer (Harshal, 13 Nov)
- [ ] NEAR AI Cloud key set (coming from NEAR Builders)
- [ ] Hold space for AI: rewrite, reply, translate, on NEAR AI Cloud
- [ ] AI receipts: model, signature verified yes or no, "attestation not checked"
- [ ] Attestation check of the TEE, not just the signature

## App
- [x] Kall-style design: masthead, cards, big lime numbers, uppercase buttons, badges
- [x] Wallet: NEAR and token balances, leash address, approvals, swap card with hold to swap, recent
- [x] Activity: every command with its receipt and badge
- [x] Leash: kill switch, agents and caps, allow and block lists, signed after Face ID
- [x] Keyboard tab: setup steps and what it does
- [x] Hold to approve, then Face ID

## Leash and server
- [x] Leash rules R0 to R7 on testnet, 21 contract tests
- [x] Agents: Payment (trusted), Inbox (untrusted), Trading
- [x] Receiver checks: exists, blocked, allowlisted, account age, paid before
- [x] Receipts for every command; server logs which client sent it
- [x] 82 server tests
- [ ] Host the server (waiting on Harshal's choice)

## Ship
- [x] Sole owner Harshal; history rewritten, no other names
- [x] README lists the pre-hackathon code from Kall Markets as baseline
- [x] README with live transactions and test counts
- [ ] README as "do X, see Y" with real tx links for the demo path
- [ ] Fresh clone of main builds, tests green
- [ ] Demo video
- [ ] Submit before 14 Nov, 23:59 UTC

## Later (after submission)
- Fancy text styles
- GIFs and stickers
- Calendar and temp mail
- Games
- Voice through the app
- Tokenized stocks (Ondo stocks aren't in the public NEAR Intents list)
- Recurring buys (DCA)
- Sputnik DAO as a team leash
- OutLayer TEE agent
- Follow KOLs and auto-trade their calls
- Key sounds and one-handed mode
- Search in the keyboard, vault shorthand, more smart chips
- NEAR Builders directory profile for hellbuddy.near (paste the API key again then; it's never saved)
