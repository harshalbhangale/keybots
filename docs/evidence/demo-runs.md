# Demo runs

Each run: `demo-reset`, then every beat through the AIRKEY server on testnet, as the keyboard calls it (scripts/demo-runs.mjs). The approve and kill-switch steps are signed with the owner's key instead of Face ID. Beats 1 to 3 pass only if their chip is up in under 2 s; *ms* is the chip there, and the command for beat 4 and the kill switch (both wait for the chain).

## 2026-11-13T10:18Z, 10 runs

| Run | Beat | Pass | ms | Tx | What came back |
|---|---|---|---|---|---|
| 1 | 1 pay | pass | 34 | [WM1jhS3U…](https://testnet.nearblocks.io/txns/WM1jhS3UZDoeB7b4mzwJtX3DQH3T88vzjHSCWXTuJcH) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 1 | 2 scam | pass | 3 | [85MQupdD…](https://testnet.nearblocks.io/txns/85MQupdDNKk2yCeKaBUHWgyxUS2wtj5A78GPGiwMFTpT) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 1 | 3 call | FAIL | 9277 | [Ez2ch9gb…](https://testnet.nearblocks.io/txns/Ez2ch9gb2mkBRCFamgd3x6wzwmE5NyqDJHzwnrUHvYg3) | Swapped 0.2857 NEAR for 0.6003 USDC on Rhea. It's in the leash. · no quote |
| 1 | 4 approve | pass | 7918 | [FJUnX549…](https://testnet.nearblocks.io/txns/FJUnX549mButJ6eDQHCMedvkk3jzdeLhiwghBvxwUe6x) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 1 | kill switch | pass | 4793 | [6PA3CiKa…](https://testnet.nearblocks.io/txns/6PA3CiKaYvba2BCm1iYLM8vaYEKkchZXR4TPXFJtNSxq) | paused 6R3NJrCo…, unpaused CJ9Wp6w1… |
| 1 | 5 AI | FAIL | 1351 |  | not on NEAR AI Cloud (openai) |
| 2 | 1 pay | pass | 3 | [2GDNVf7e…](https://testnet.nearblocks.io/txns/2GDNVf7eyHxYhGaFhh29PeQh3hqWdyQgRE3PdXivnGzj) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 2 | 2 scam | pass | 3 | [DYwEDRin…](https://testnet.nearblocks.io/txns/DYwEDRinDQgWgUppVFL3kzH5WC3jfPYqVFP6rFeEqCMr) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 2 | 3 call | pass | 1270 | [4h1upR7n…](https://testnet.nearblocks.io/txns/4h1upR7nxagQcj5BXNhrJib8jhKiG9mKmCD4v4AW5Qph) | Swapped 0.2857 NEAR for 0.6002 USDC on Rhea. It's in the leash. · quote 0.2857 NEAR → 0.012375974 SOL |
| 2 | 4 approve | pass | 2887 | [7iWocJrV…](https://testnet.nearblocks.io/txns/7iWocJrVBDWfTbZNf9K6ph3fmskh4EFohL4PydyBS7Rv) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 2 | kill switch | pass | 3560 | [Fw2brwRm…](https://testnet.nearblocks.io/txns/Fw2brwRmDiF9e4WEufsgpQBWuzhFzKVSov1sc6WjrtWM) | paused 2NkEW4gj…, unpaused 7bUWjPnW… |
| 2 | 5 AI | FAIL | 1182 |  | not on NEAR AI Cloud (openai) |
| 3 | 1 pay | pass | 3 | [F4hkDEcf…](https://testnet.nearblocks.io/txns/F4hkDEcfX7SHriT1ngwX2SngNayHVkAVdx9EqtL4n1uA) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 3 | 2 scam | pass | 1 | [3a7CrBW1…](https://testnet.nearblocks.io/txns/3a7CrBW1oxmoEQMwYe4u8E4ZezHfynDXnrh6rvGFyCfD) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 3 | 3 call | pass | 1046 | [75bbTtH7…](https://testnet.nearblocks.io/txns/75bbTtH7R9XUB7PWvSZNKCpLsdwhVW8aZ9BMANx97MqQ) | Swapped 0.2857 NEAR for 0.6002 USDC on Rhea. It's in the leash. · quote 0.2857 NEAR → 0.01236507 SOL |
| 3 | 4 approve | pass | 6558 | [DNkn1TeH…](https://testnet.nearblocks.io/txns/DNkn1TeHLNkDp5Z1H1qwYQd2az72dDd8rMuDZBrZ8Wup) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 3 | kill switch | pass | 3302 | [x5M4KXpB…](https://testnet.nearblocks.io/txns/x5M4KXpBnaRCAj1uWKbhXVocuAXhbzSkbm1gezp41f3) | paused 84H3uom7…, unpaused 5NwJXY3c… |
| 3 | 5 AI | FAIL | 1982 |  | not on NEAR AI Cloud (openai) |
| 4 | 1 pay | pass | 4 | [4XMzMCon…](https://testnet.nearblocks.io/txns/4XMzMConrGR9fDnV2DsEdsxTs6TUjXYEMqVvoWnZMsdx) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 4 | 2 scam | pass | 2 | [6Y9Hx1Nv…](https://testnet.nearblocks.io/txns/6Y9Hx1Nvjh3u2oh7k4vJ9NH6x5BYcrJDpbnsfGcvm7Er) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 4 | 3 call | pass | 1302 | [GnVPoyZx…](https://testnet.nearblocks.io/txns/GnVPoyZxJ7fTVPidPkkPPxp9ZjnN6f8YoSCuGAuFYp3Z) | Swapped 0.2849 NEAR for 0.5985 USDC on Rhea. It's in the leash. · no quote |
| 4 | 4 approve | pass | 7260 | [BNVVa6S6…](https://testnet.nearblocks.io/txns/BNVVa6S6mXvzvjSoRmYXbjemoA51D5gza4FPCzk8vjGC) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 4 | kill switch | pass | 7558 | [J9QKTnP3…](https://testnet.nearblocks.io/txns/J9QKTnP3o6dN9s73vXSLwkMqZzbMkR2iBTzJjgKUrzb5) | paused HR4cCAVK…, unpaused D8Exeey4… |
| 4 | 5 AI | FAIL | 3496 |  | not on NEAR AI Cloud (openai) |
| 5 | 1 pay | pass | 5 | [8HzVcQMC…](https://testnet.nearblocks.io/txns/8HzVcQMCAAtoGpywkhkLw3UCVusGALAsJyoYegfyrRQ9) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 5 | 2 scam | pass | 2 | [5vbuJD9f…](https://testnet.nearblocks.io/txns/5vbuJD9fMzBc5Wks3MoYnBXim4pRKX26ofvEPdDU7tAb) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 5 | 3 call | FAIL | 2745 | [Ct1L7Dck…](https://testnet.nearblocks.io/txns/Ct1L7Dck7ikRVvQ2nMx7bvYGyDG1DAbs3Y6XZ3ZqVvuM) | Swapped 0.2849 NEAR for 0.5985 USDC on Rhea. It's in the leash. · no quote |
| 5 | 4 approve | pass | 7807 | [DNgTw1Kr…](https://testnet.nearblocks.io/txns/DNgTw1Kr6RWAqwpcUdt2HDhzKsE8P31ByAxnLrRcRzT3) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 5 | kill switch | pass | 8595 | [3hLQvo57…](https://testnet.nearblocks.io/txns/3hLQvo57WuHArZTmFKzzYqmWHyXSRzDFFfj5kj6ztFQR) | paused 6TthBdEc…, unpaused Fw7GEQhc… |
| 5 | 5 AI | FAIL | 5237 |  | not on NEAR AI Cloud (openai) |
| 6 | run | FAIL | 0 |  | error: fetch failed |
| 7 | run | FAIL | 0 |  | error: fetch failed |
| 8 | 1 pay | pass | 6 | [HV1DVb5n…](https://testnet.nearblocks.io/txns/HV1DVb5nzLEiiSBvtJRDMSHwk8qVYy2QcEpyqb8ZrsFu) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 8 | 2 scam | pass | 1 | [8oq884wc…](https://testnet.nearblocks.io/txns/8oq884wciMwVbSm7ifPpEk5pr6Z53JDsYAPAgvddKs8F) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 8 | 3 call | pass | 1674 | [5CxA3vPU…](https://testnet.nearblocks.io/txns/5CxA3vPUFaZAwpQVKeKvrQFMsENvRcVuzHB8QaW6THak) | Swapped 0.2857 NEAR for 0.6002 USDC on Rhea. It's in the leash. · no quote |
| 8 | 4 approve | pass | 7684 | [GWfVLhrD…](https://testnet.nearblocks.io/txns/GWfVLhrDDw4RQGhfTrv1CNv6dL9MYtTXompi2Eou1w44) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 8 | kill switch | pass | 4515 | [HDG5zKAD…](https://testnet.nearblocks.io/txns/HDG5zKADsnHgXvEuPyxAQDedU7nifzjhNGvyTubVB1zd) | paused 8UEd3qgw…, unpaused 5WUfM4fZ… |
| 8 | 5 AI | FAIL | 8037 |  | not on NEAR AI Cloud (openai) |
| 9 | run | FAIL | 0 |  | error: fetch failed |
| 10 | 1 pay | pass | 3 | [23ixR5Ee…](https://testnet.nearblocks.io/txns/23ixR5EepG2bYSSSKXy511hq1Zc5pSv4uoAcpu3R3VNQ) | Paid 0.2 NEAR to friend.airkey-harshal.testnet |
| 10 | 2 scam | pass | 2 | [GUyK3DUb…](https://testnet.nearblocks.io/txns/GUyK3DUbNvesbZTe4jdDDPnBEL84WDRpoVzCciLsaaFU) | Blocked by the leash (R3): drain.airkey-harshal.testnet is blocked: reported by inbox.airkey-harshal.testnet: asked for an urgent payment to |
| 10 | 3 call | pass | 1094 | [HvJjVCxf…](https://testnet.nearblocks.io/txns/HvJjVCxfd9Q99DJ7bjCK3sH4YduHkuH1qACBwoJkkeWR) | Swapped 0.2857 NEAR for 0.6002 USDC on Rhea. It's in the leash. · quote 0.2857 NEAR → 0.012311304 SOL |
| 10 | 4 approve | pass | 3862 | [AgHVp2Xt…](https://testnet.nearblocks.io/txns/AgHVp2XtdNqvkYcZ1JgBxa1HXptA9iNTwr7WdCzCrVEK) | Needs your approval: 0.4 NEAR to vendor.airkey-harshal.testnet. New account: created 0 day(s) ago. You've never paid this account. |
| 10 | kill switch | pass | 12164 | [DSzqFD4q…](https://testnet.nearblocks.io/txns/DSzqFD4q3yYFsKwbcSg1gTcUG63Frdn2erivB3cmMiF9) | paused 9GxRy4N9…, unpaused 6ttEEpm1… |
| 10 | 5 AI | FAIL | 4476 |  | not on NEAR AI Cloud (openai) |

5 beat(s) failed (beat 5 counts only with a NEAR AI Cloud key).
