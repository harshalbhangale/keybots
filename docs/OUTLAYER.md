# OutLayer custody for the agents' keys

Status: plan and code on branch `outlayer-custody`, testnet only. What is proven
is listed in [evidence/outlayer-testnet.md](evidence/outlayer-testnet.md);
anything not listed there is not proven.

## Why

Today the AIRKEY server signs `leash.pay` and `leash.swap` with function-call
keys it keeps in `keys/` (gitignored). Whoever reads that folder can act as an
agent, within the leash's rules.

With OutLayer custody the agent's NEAR key is derived and used inside
OutLayer's keystore, which runs in Intel TDX. The server never has the key. It
holds an OutLayer API key (`wk_...`, in `server/.env`) that asks OutLayer to
sign a call.

The leash does not change. It still decides every payment by its rules
(RULES.md), checking `predecessor_account_id`. Only the account that signs
changes: the agent becomes the OutLayer wallet's implicit account (64 hex
characters) instead of `pay.<owner>`.

## How

| Piece | What it does |
|---|---|
| `POST /register` | Once per agent. Creates an OutLayer wallet and returns its `wk_` key (shown once) and its NEAR implicit account. Needs Harshal's yes before it is called. |
| `GET /wallet/v1/address?chain=near` | The agent's NEAR account and public key. |
| `scripts/setup-outlayer.mjs` | For each agent: read its address, send it 0.3 testnet NEAR for gas from the owner, and `add_agent` it on the leash with the same tier and caps as the current agent. |
| `server/src/outlayer.ts` | A `Chain` that sends `pay` and `swap` through `POST /wallet/v1/call` and reads the result (decision, events, logs) from the transaction on NEAR RPC. Views still go through `near.ts`. |
| `AIRKEY_SIGNER=outlayer` | Turns it on. Unset, the server uses the local keys exactly as before. |
| `POST /wallet/v1/encrypt-policy` + `sign-policy` | Optional second lock: an OutLayer policy that only allows `call`, only to the leash. Not required for the leash's rules to hold. |

Env when the switch is on (`server/.env`, gitignored):

```
AIRKEY_SIGNER=outlayer
OUTLAYER_API=https://testnet-api.outlayer.ai
AIRKEY_AGENT_TRUSTED=<pay agent implicit account>
AIRKEY_AGENT_UNTRUSTED=<inbox agent implicit account>
AIRKEY_AGENT_TRADE=<trade agent implicit account>
OUTLAYER_KEY_TRUSTED=wk_...
OUTLAYER_KEY_UNTRUSTED=wk_...
OUTLAYER_KEY_TRADE=wk_...
```

## What OutLayer does and does not give us

- The agent key is not on the AIRKEY server. Someone who steals `server/.env`
  gets the `wk_` keys, which can ask OutLayer to sign for that agent, so they
  can still do what the agent can do, within the leash's rules and any
  OutLayer policy. A `wk_` key can be revoked at OutLayer; a leaked local key has
  to be deleted on chain.
- The agent's implicit account holds a full-access key (inside the TEE), not a
  function-call key. It can spend its own gas balance (0.3 NEAR) anywhere. It
  cannot move the leash's money except through `pay`/`swap`, which the leash
  rules decide, and it cannot call owner methods (`add_agent`, `withdraw`,
  `set_paused`...), which require the owner.
- OutLayer's API does not return a per-call attestation. Trust in the keystore
  comes from OutLayer's worker attestation (TDX quotes checked on chain by its
  register contract; see their WORKER_ATTESTATION.md). The evidence file
  records what we could check ourselves and says what we could not.
- OutLayer's coordinator is closed source and a third-party service. If it is
  down, agents under the switch cannot pay; the default local path still works.
