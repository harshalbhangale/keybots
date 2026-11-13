# OutLayer custody: testnet evidence

Run on 13 Nov 2026 against `https://testnet-api.outlayer.ai` and
`leash.airkey-harshal.testnet`. Raw output:
[outlayer-testnet.json](outlayer-testnet.json), from
`scripts/prove-outlayer.ts`. Setup was done by `scripts/setup-outlayer.mjs`.

## Agents

Each agent is an OutLayer wallet. Its NEAR account is an implicit account with
exactly one access key, the one OutLayer's keystore derived (checked with
`view_access_key_list`). The AIRKEY server holds only the OutLayer API keys, in
`server/.env`, which is gitignored.

| Role | NEAR account | Gas from owner | `add_agent` | OutLayer policy |
|---|---|---|---|---|
| pay (trusted, 0.5/1 NEAR) | `d8dc39a8…96b1f9` | [58GzW1Uw…](https://testnet.nearblocks.io/txns/58GzW1UwrzmRCD8y8mTrA3YSyS4PzHZ6CGP2ceAWfhac) | [4VdfismW…](https://testnet.nearblocks.io/txns/4VdfismWbqaPS4d8HbZKytqbKdVvN4hzFXpwzG2fUxqJ) | [8SecwPqb…](https://testnet.nearblocks.io/txns/8SecwPqbxwRqEfLQSkaTnTfKy6imPKaJ9M6bKsp5xkPc) |
| inbox (untrusted, 0.5/1 NEAR) | `e74de3f9…a2c627` | [HhjgiuYT…](https://testnet.nearblocks.io/txns/HhjgiuYTFerWM3wWRzkYnQ6S1EkpSLcYytMsm9cs6RkQ) | [7qSaavYP…](https://testnet.nearblocks.io/txns/7qSaavYPg5AMojMG4yJCumrvn4ybdxDg1Tm7s86MpQrn) | [DauJG59A…](https://testnet.nearblocks.io/txns/DauJG59A5rnFJVPrh16J8LsQ3KZxDenutKJKezbN9XdS) |
| trader (trusted, 1/2 NEAR) | `a3b5fd06…3b9ad8` | [4KdjqoL1…](https://testnet.nearblocks.io/txns/4KdjqoL1DvSBWNzy5dsWf6ht2MGYwUxSMJ5mpBW7zLqG) | [AMXp8NLR…](https://testnet.nearblocks.io/txns/AMXp8NLRiHKjxtgLYXQKY7uXyW3GGtoQZaGniyoJwWn9) | [3RgDtvAJ…](https://testnet.nearblocks.io/txns/3RgDtvAJXmvPurwYhsXS7WXcmqYZG8j7daLRFL6Wphdh) |

Full accounts:
`d8dc39a816372c3ad171de47b26f331330884b8cdaa58e8bebb347686c96b1f9`,
`e74de3f95b541381f905defb0e47ff1401954541dfc1055bd138ee40baa2c627`,
`a3b5fd06b6eeab944af0c881e4651412bb5cc1423fdf13eca00c2ef4333b9ad8`.

Each policy allows only `call`, and only to `leash.airkey-harshal.testnet`.
`GET /wallet/v1/policy` returns it as stored, version 1.

## Results

Steps 1 to 3 went through `server/src/outlayer.ts`, the same code the server
uses when `AIRKEY_SIGNER=outlayer` is set. Steps 4 to 6 call OutLayer's API
directly, the way someone holding an agent's API key could.

| # | What | Result | Proof |
|---|---|---|---|
| 1 | pay agent pays `friend` 0.01 NEAR | leash: **paid** | [HirZn4VK…](https://testnet.nearblocks.io/txns/HirZn4VK47ftSXgCpG7ymsVichUEXhiKMduHkCS3Jq77) |
| 2 | inbox agent pays the pasted scammer `drain` | leash: **blocked, R3** (on the blocklist) | [AqUBD8Jt…](https://testnet.nearblocks.io/txns/AqUBD8JtATSxhsgGmuiYFKNq4QZW3vqcTVSiXqL648Fu) |
| 3 | pay agent pays 0.6 NEAR (cap 0.5) | leash: **blocked, R4** | [C8ciirrh…](https://testnet.nearblocks.io/txns/C8ciirrhnL88funddjo1gjBSzrmcQSxarwdsYdGBaCgf) |
| 4 | inbox agent calls the owner's `withdraw` | OutLayer signed and sent it; the leash **panicked: "Only the owner can do this"** | [B5BnuEks…](https://testnet.nearblocks.io/txns/B5BnuEkss1gi7PcAjD1i5geCTGSuosnXNzdBpaff8fhK) |
| 5 | inbox agent transfers its gas NEAR to `drain` | OutLayer **403 policy_denied**: "Transaction type 'transfer' is not allowed by policy" | no transaction (refused before signing) |
| 6 | inbox agent calls `wrap.testnet` | OutLayer **403 policy_denied**: "Address 'wrap.testnet' is not in whitelist" | no transaction (refused before signing) |

## What this proves

- An agent whose key is held by OutLayer can pay through the leash, and the
  leash decides the payment exactly as it does for a locally signed agent
  (steps 1 to 3).
- With an agent's OutLayer API key you can do only what the leash allows that
  agent. Owner methods fail on chain (step 4). With the policy set, the wallet
  will not sign a transfer of its own NEAR, or a call to any contract except the
  leash (steps 5 and 6).
- The agents' private keys are not in this repo or on the AIRKEY server. Only
  OutLayer's keystore holds them.

## What it does not prove

- **Attestation.** OutLayer's wallet API returned no TDX quote or attestation
  for these calls, and we did not verify one ourselves. OutLayer's docs say its
  workers' keys are added to `worker.outlayer.testnet` only after the register
  contract verifies a TDX quote. That account has 60 function-call keys scoped
  to `resolve_execution`. That is OutLayer's claim about its execution workers,
  not something this run checked about the keystore that signed these calls.
- **The server switch.** `AIRKEY_SIGNER=outlayer` in `server/src/index.ts` is
  not merged yet. The code path above is the one the switch selects, but the
  running server and app were not exercised through it.
- **Swaps.** No swap was sent through OutLayer on testnet. The signer's swap
  path is covered only by the fake-server test.
- **The `wk_` keys.** They are bearer keys. Anyone holding one gets steps 1 to
  6 above, nothing more. Losing `server/.env` is still a real incident, just a
  smaller one than losing a NEAR key.
- `GET /wallet/v1/policy` reports `controller` as the wallet's own key, not the
  owner account, even though the owner sent `store_wallet_policy`. We did not
  test who can change the policy.
