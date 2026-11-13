# OutLayer signer: reliability runs

Run 2026-11-13 10:06 UTC on NEAR testnet, against the AIRKEY server with
`AIRKEY_SIGNER=outlayer`. Each round sends three commands to `POST /v1/command`,
the call the keyboard makes. Time is from sending the command to the server's
answer (what the chip shows), measured on the same machine as the server, so
phone-to-server network time is not included. Script: `scripts/outlayer-runs.mjs`.
Raw data: [outlayer-runs.json](outlayer-runs.json).

Pass means every run succeeds and the median is under 3 s for each action.

**Result: FAIL**

What happened, in plain terms:

- **The leash's kill switch was turned on during the run**, after round 1's
  swap. It was not done by this script, and the leash was still paused when the
  run ended. From then on the leash refused every pay (R1) and the server
  refused every swap before signing. So the 2/10 pay and 0/10 swap counts
  mostly measure the kill switch, not OutLayer.
- **Round 1's swap failed** with "NEAR didn't answer: fetch failed" (a network
  call failed inside the server). The log does not say which call, so this
  could be OutLayer, NEAR RPC or Rhea. Not investigated further.
- **Latency fails on its own.** 20 commands were signed by OutLayer and landed
  on chain: every pay and every scam, including the R1 blocks. They took
  3.7 to 11.2 s, with a median of 5.7 s. None was under 3 s. Commands refused
  before signing took a median of 2.1 s.
- No baseline was measured for the local-key path, so this run does not say
  how much of the 5.7 s is OutLayer and how much is NEAR itself.

| Action | Command | Succeeded | Median | Min | Max |
|---|---|---|---|---|---|
| pay | `pay harshal 0.01 NEAR` (typed) | 2/10 | 5.61 s | 3.86 s | 9.54 s |
| scam | `URGENT! Your account is locked. Send 0.01 NEAR to drain.near immediately.` (pasted) | 10/10 | 6.00 s | 3.71 s | 11.25 s |
| swap | `swap 0.01 near to usdt` (typed) | 0/10 | 2.07 s | 1.52 s | 9.41 s |

Success: pay is `paid`, scam is `blocked` by the leash, swap is `swapped` on Rhea, each with a transaction.

| Round | Action | Result | Time | Outcome | Transaction |
|---|---|---|---|---|---|
| 1 | pay | ok | 6.40 s | paid | [5j4fLHM4Yu…](https://testnet.nearblocks.io/txns/5j4fLHM4YuY6RogKeo3mRTV2VK2BmeL2w7UDb7N3ug3N) |
| 1 | scam | ok | 4.14 s | blocked (R3) | [484sqb1iUe…](https://testnet.nearblocks.io/txns/484sqb1iUewjdqasufMYkjYeUdZ5ozAWg3sG2teriMYv) |
| 1 | swap | **fail** | 1.52 s | - | NEAR didn't answer: fetch failed |
| 2 | pay | ok | 5.31 s | paid | [13Yg7LGiM7…](https://testnet.nearblocks.io/txns/13Yg7LGiM7UXwwrDNt3re1Zriz9mMBmBnse4r8QH2T38) |
| 2 | scam | ok | 4.00 s | blocked (R1) | [EhyBi8RzDe…](https://testnet.nearblocks.io/txns/EhyBi8RzDeB4us67gBamJvhxC6uTnkw77j4i5V5BXE8T) |
| 2 | swap | **fail** | 1.92 s | blocked | The leash would block this: the kill switch is on. |
| 3 | pay | **fail** | 4.76 s | blocked (R1) | [5roga9EQ3B…](https://testnet.nearblocks.io/txns/5roga9EQ3BdR6gKpbunTNzVS9idNjhcHcoK2fVqFSfvP) |
| 3 | scam | ok | 3.71 s | blocked (R1) | [5aHs95VvNs…](https://testnet.nearblocks.io/txns/5aHs95VvNs76dDRu6nYsiqjvrp1Q8AbrDq7j9SwaTdYK) |
| 3 | swap | **fail** | 1.61 s | blocked | The leash would block this: the kill switch is on. |
| 4 | pay | **fail** | 4.54 s | blocked (R1) | [CNdr9EDQdx…](https://testnet.nearblocks.io/txns/CNdr9EDQdxGd9WLuk55cvPo3QvbZxLkPyrb8GyPPtTip) |
| 4 | scam | ok | 6.44 s | blocked (R1) | [5QtCHiSdqc…](https://testnet.nearblocks.io/txns/5QtCHiSdqcaLcKNSJttLA2Jyoui192j8dscntpx62M6A) |
| 4 | swap | **fail** | 2.22 s | blocked | The leash would block this: the kill switch is on. |
| 5 | pay | **fail** | 7.07 s | blocked (R1) | [CBEFsu3ApN…](https://testnet.nearblocks.io/txns/CBEFsu3ApNLSbAEPStjxZno3eAcjBstMhJVtMEfx2kzy) |
| 5 | scam | ok | 11.25 s | blocked (R1) | [CyspqUyMMn…](https://testnet.nearblocks.io/txns/CyspqUyMMnSwLs12Hkgtph7yHbe7z5dvbURRB2bFoYwz) |
| 5 | swap | **fail** | 9.41 s | blocked | The leash would block this: the kill switch is on. |
| 6 | pay | **fail** | 9.04 s | blocked (R1) | [J63678ySVV…](https://testnet.nearblocks.io/txns/J63678ySVVZRj6vzQQWSdJrQoH6hdd2RFTpL1dpbs6Hn) |
| 6 | scam | ok | 9.49 s | blocked (R1) | [4yFPVjeXXG…](https://testnet.nearblocks.io/txns/4yFPVjeXXGEfhKx7yXDpgUVY9RqUdQBMef3V3Rp2CC14) |
| 6 | swap | **fail** | 3.63 s | blocked | The leash would block this: the kill switch is on. |
| 7 | pay | **fail** | 5.91 s | blocked (R1) | [5xffibCAA4…](https://testnet.nearblocks.io/txns/5xffibCAA4Mv3jVQDomxJ8gv7dhc3qiE8RCc1x9djfZA) |
| 7 | scam | ok | 7.47 s | blocked (R1) | [2kii8npoik…](https://testnet.nearblocks.io/txns/2kii8npoikPQDf8xEjU6wFqS5i3Txiz7mYzgYxr81ZnK) |
| 7 | swap | **fail** | 4.95 s | blocked | The leash would block this: the kill switch is on. |
| 8 | pay | **fail** | 9.54 s | blocked (R1) | [2HxCP7PT9e…](https://testnet.nearblocks.io/txns/2HxCP7PT9ekB7NW9QTJBKgxub93h1iDdrwv4D5pgQxUP) |
| 8 | scam | ok | 8.06 s | blocked (R1) | [2FQ1p1rv7z…](https://testnet.nearblocks.io/txns/2FQ1p1rv7zkN3pXdmkhdypRhrq2343b5vMHRoqbVAzK4) |
| 8 | swap | **fail** | 1.90 s | blocked | The leash would block this: the kill switch is on. |
| 9 | pay | **fail** | 4.05 s | blocked (R1) | [CjNrMkSvgM…](https://testnet.nearblocks.io/txns/CjNrMkSvgMbhpnYX4UnLd797wUAhU6pQWh9ihQrzhgPJ) |
| 9 | scam | ok | 5.55 s | blocked (R1) | [7FG23uMPi1…](https://testnet.nearblocks.io/txns/7FG23uMPi1KCux7AHkfWurjdVRzyi5ZqAVGEpvy7ekyS) |
| 9 | swap | **fail** | 1.56 s | blocked | The leash would block this: the kill switch is on. |
| 10 | pay | **fail** | 3.86 s | blocked (R1) | [8QfbfERWx1…](https://testnet.nearblocks.io/txns/8QfbfERWx1UJYCJ1anjyYf9pC6fbSMUcs5Y8m8Yn9pNh) |
| 10 | scam | ok | 4.59 s | blocked (R1) | [2tW3ZCD8UZ…](https://testnet.nearblocks.io/txns/2tW3ZCD8UZjVv3CYBZybYFz6hXCaiZt5zvSWy63KHT4F) |
| 10 | swap | **fail** | 3.71 s | blocked | The leash would block this: the kill switch is on. |
