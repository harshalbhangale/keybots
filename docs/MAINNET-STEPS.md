# Mainnet: the owner's runbook for hellbuddy.near

This puts Spend Limits on NEAR mainnet under **hellbuddy.near**. Real money. Nothing here has been sent yet: every transaction below is signed only when Harshal runs that one step himself, after reading what it will do.

## What it builds

| Account | What it is | Its key |
|---|---|---|
| `hellbuddy.near` | The owner. Approves, blocks, stops everything, takes money back. | Your own wallet, plus one setup key you add and remove |
| `limits.hellbuddy.near` | Spend Limits: holds the money and checks every payment and swap | A full-access key in `keys/` (only to update the code; delete it to lock the code) |
| `pay.hellbuddy.near` | Pay Agent (trusted): pays for what you type. 0.2 NEAR a payment, 0.5 a day | Function-call key for Spend Limits: `pay`, `report` |
| `inbox.hellbuddy.near` | Inbox Agent (untrusted): acts on pasted or inbound text. 0.1 NEAR a payment, 0.2 a day | Function-call key for Spend Limits: `pay`, `report` |
| `trader.hellbuddy.near` | Trading Agent (trusted): swaps. 0.3 NEAR a trade, 0.6 a day | Function-call key for Spend Limits: `pay`, `report`, `swap` |

Contacts: **none**. The address book stays empty on mainnet, and there is no demo "scam" account. Add only accounts you control, later, with `AIRKEY_CONTACTS`.

Swaps on mainnet: NEAR to USDC or USDT runs on Rhea (`v2.ref-finance.near`, pools 4512 and 6063) and the tokens land back in Spend Limits. NEAR to anything else NEAR Intents lists (SOL, BTC…) goes through a NEAR Intents deposit address; the token lands in hellbuddy.near (a NEAR token) or in hellbuddy.near's NEAR Intents balance (a token from another chain, withdrawn at app.near-intents.org). The server refuses any mainnet swap above **$1** (`AIRKEY_MAINNET_USD_CAP`).

## What it costs (dry run, 14 Nov 2026)

Read from `https://rpc.mainnet.near.org`. Gas price 100,000,000 yoctoNEAR a unit (1 TGas ≈ 0.0001 NEAR). Contract code 255,197 bytes.

| Step | What | NEAR |
|---|---|---|
| 1 | Create `limits.hellbuddy.near`, deploy, start it | 2.6520 (2.5520 storage for the code at 1 NEAR per 100 KB + 0.1 for its state) |
| 2–4 | Create the three agents | 0.1000 each, 0.3000 in all (their own gas money) |
| 5 | Register the agents with their limits | 3 yoctoNEAR |
| 6 | Fund Spend Limits | 0.5000 (`--fund` to change) |
| 7–9 | Register Spend Limits on wNEAR, USDC, USDT | 0.00125 each |
| 10 | Optional: let the Trading Agent sell USDC/USDT back (1 a trade, Rhea only) | 2 yoctoNEAR |
| | Gas, at most | about 0.023 |
| | **Total** | **3.4788 NEAR** |

**hellbuddy.near holds 0.9792 NEAR today (0.9773 free): 2.5015 NEAR short.** Top it up to at least 3.5 NEAR before step 1.

Where it goes: 2.55 NEAR stays locked as storage for the code while `limits.hellbuddy.near` exists (it comes back only if that account is deleted). 0.6 NEAR sits in Spend Limits for the agents to spend; you can take it back any time with `withdraw`. 0.3 NEAR is the agents' gas money.

## Steps

On your Mac, from the repo root. Build the contract first if `contracts/leash/target/near/airkey_leash.wasm` is missing:

```
cd contracts/leash && cargo near build non-reproducible-wasm && cd ../..
cd scripts && npm install          # every npm command below runs in scripts/
```

### 1. Make a setup key and add it to hellbuddy.near

```
npm run new-owner-key
```

It saves a new key to `keys/hellbuddy.near.json` (gitignored, readable only by you) and prints **only** its public key, with the exact command to add it from your own wallet:

```
near account add-key hellbuddy.near grant-full-access use-manually-provided-public-key ed25519:<the printed key> network-config mainnet
```

NEAR CLI asks how you sign (seed phrase, Ledger or keychain) and shows the transaction first. This one is signed by you, in your wallet.

### 2. Read the plan

```
npm run setup-mainnet
```

A dry run: it reads the chain and prints every step with its signer, receiver, method, deposit and gas, a running total, and whether hellbuddy.near has enough. It signs nothing. Check that it says **enough** before going on.

### 3. Send the steps, one at a time

```
npm run setup-mainnet -- --yes --step 1
npm run setup-mainnet -- --yes --step 2
...
npm run setup-mainnet -- --yes --step 9
npm run setup-mainnet -- --yes --step 10   # optional
```

Each run prints the step again, sends that one transaction, and prints its nearblocks.io link. It refuses to run a step out of order, skips a step the chain shows as done, and stops if the key in `keys/hellbuddy.near.json` isn't a full-access key of hellbuddy.near. Run `npm run setup-mainnet` again between steps to see where you are. New account keys go to `keys/` and are never printed.

### 4. Point the server at mainnet

In `server/.env` (gitignored):

```
NEAR_NETWORK=mainnet
AIRKEY_MAINNET_USD_CAP=1
```

With `NEAR_NETWORK=mainnet` the server uses hellbuddy.near, `limits.hellbuddy.near`, the three agents above, Rhea's mainnet pools and nearblocks.io links. It holds only the agents' function-call keys from `keys/`, never yours.

### 5. Remove the setup key

When setup is done:

```
near account delete-keys hellbuddy.near public-keys ed25519:<the printed key> network-config mainnet
```

then delete `keys/hellbuddy.near.json`. Approving payments from the phone uses the phone's own key, added separately.

## Decisions for the owner

- **The 2.5 NEAR storage.** It's the price of putting the 255 KB contract on chain, and it's more than the "$0.50 till submission" budget. It's locked, not spent, but it has to be there.
- **Locking the code.** Step 1 gives `limits.hellbuddy.near` a full-access key so the code can be fixed later. Delete that key to make the code unchangeable.
- **Funding.** 0.5 NEAR by default (`--fund`). The agents can never spend more than their daily limits, whatever is in it.
- **Step 10.** Only needed if the Trading Agent should sell USDC or USDT back for NEAR. Each full trade (1 token) counts for at least 0.25 NEAR against its limits.
