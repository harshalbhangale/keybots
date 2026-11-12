# Testnet end-to-end run

Run on 2026-11-12T16:43:43.110Z against [`leash.airkey-harshal.testnet`](https://testnet.nearblocks.io/address/leash.airkey-harshal.testnet) by `scripts/e2e-testnet.mjs`.

| # | Step | Expected | Got | Transaction |
|---|---|---|---|---|
| 1 | pay agent → friend 0.1 (typed) | paid | ✅ paid | [6KvkkSbWwt…](https://testnet.nearblocks.io/txns/6KvkkSbWwtwxTZKYocBvQc1VqMythvwehAPj5dQ7nrwc) |
| 2 | inbox agent → vendor 0.1 (pasted invoice) | pending | ✅ pending (R6) | [AsWZ9PLFPD…](https://testnet.nearblocks.io/txns/AsWZ9PLFPDDUaSy83XY24X2hSDXXhZXW6F4ndXc3wC8J) |
| 3 | injected: inbox agent → drain 5 | blocked | ✅ blocked (R4: Over the per-payment cap of 0.5 NEAR) | [HMeo4MYzcL…](https://testnet.nearblocks.io/txns/HMeo4MYzcLWXSpkt9sn9qbnXBFfax4fC24nf2BHzD2kt) |
| 4 | after report: pay agent → drain 0.01 | blocked | ✅ blocked (R3; report https://testnet.nearblocks.io/txns/JC5hEwaByGt8v8fFDQwRvbdoEtkRU775kJARprBLCJEk) | [CyYNttqApc…](https://testnet.nearblocks.io/txns/CyYNttqApc5UBjXBd4zyWkc3toiajpzTC4N4ouDsJACj) |
| 5 | owner approves the vendor invoice | paid | ✅ paid | [GutSnUrdXJ…](https://testnet.nearblocks.io/txns/GutSnUrdXJNWMf2rszpsBbT7i4gEfeFa6B9xUEd1o82H) |
| 6 | pay agent signs a direct transfer to drain | rejected | ✅ rejected (Access key requires full access) | rejected before reaching the chain |
| 7 | pay agent calls set_paused | rejected | ✅ rejected (Access key does not allow method set_paused) | rejected before reaching the chain |
| 8 | pay to a missing account rolls back | rolled back | ✅ rolled back | [38S5npV7jA…](https://testnet.nearblocks.io/txns/38S5npV7jADFFio8jZUM19212EKphy6x9EAfPLTZuAEd) |
| 9 | kill switch on: pay agent → friend | blocked | ✅ blocked (R1; switch https://testnet.nearblocks.io/txns/261fTAQdBmw6cWk94MdM26mgWxZbzv6GFiJkxKgecU5g) | [GDpBrrw3L6…](https://testnet.nearblocks.io/txns/GDpBrrw3L6DNfAbLHzUihi4LCjegfoHFeqZcumCNwm1x) |
