# AIRKEY demo video kit

Recording day is just capture. This folder turns one screen recording into the final 2:00–2:30, 1080p video with an intro card, timed captions and an end card.

```bash
cd landing/video
npm install                       # once: the SVG renderer for the cards
./make.sh ~/Desktop/recording.mov # writes airkey-demo.mp4
```

## What it makes

1. **Intro card** (2 s): the AIRKEY mark and "Your keyboard is the AI. NEAR is the leash."
2. **Your recording** with a caption for each beat. A portrait iPhone recording sits on the dark AIRKEY background with the caption beside it; a landscape recording fills the frame with a lower-third caption. Your recording's audio (voice-over) is kept.
3. **End card** (4 s): the line, the repo URL and "Built at NEAR HACKATHON 2026".

The script warns if the total isn't between 2:00 and 2:30.

## After recording: set the caption times

Open `beats.json` and set `start` / `end` (seconds into **your recording**, not the final video) for each beat, then run `./make.sh` again. Edit `title` / `sub` there too; `npm run cards` re-renders the cards and captions into `build/` (open the `.png` files to check them).

| # | Beat | Caption |
|---|---|---|
| 1 | Hook | A scam lands in your DMs. |
| 2 | Pay by typing, PAID chip, receipt shared | Pay by typing |
| 3 | The scam is blocked | The AI is fooled. The leash isn't. |
| 4 | A pasted call becomes a trade | A call becomes a trade |
| 5 | New receiver, APPROVE?, Face ID | Someone new? Approve. |
| 6 | Hold space, private AI rewrite | Hold space: private AI on NEAR AI Cloud (TEE), signature verified; attestation not verified yet |
| 7 | Kill switch | One kill switch |

**Check before the final cut:** beats 4 and 6 must match what the app really does on the day. As of 14 Nov a copied call can be checked but only what you type trades, and the AI rewrite answers on NEAR AI Cloud. If either isn't in the recording, delete its entry from `beats.json`.

## Recording tips

- iPhone: Control Center › Screen Recording (hold for the microphone if you narrate). AirDrop the file to the Mac.
- Simulator: `xcrun simctl io booted recordVideo ~/Desktop/recording.mov` (Ctrl-C to stop).
- Keep the full take under 2:24 so it lands between 2:00 and 2:30 with the cards.

## The X post

The hackathon asks for a public X post with the video. A draft is in `../SUBMISSION-DRAFT.md`; it must say it was built at NEAR HACKATHON and tag @NEARProtocol and #NEARHackathon.
