#!/usr/bin/env bash
# Copies the real app screens the landing page shows from docs/screens/ into
# landing/public/screens/ as 630 px wide JPEGs.
#   bash landing/brand/screens.sh
# The pay screen was captured before the rename, so two small "AIRKEY" labels on it
# (the back link and the space bar) are painted over with "Messages" and "keybots".
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../docs/screens"
out="$here/../public/screens"
mkdir -p "$out"
jpg() { ffmpeg -loglevel error -y -i "$src/$1.png" -vf "scale=630:-2" -q:v 3 "$out/$2.jpg"; }

# Two hero screens; HERO picks the one the page shows (default: spotlight).
#   spotlight: the real Spotlight capture with the Keybots panel (mainnet); the Keybots app
#              icon and label replace Reminders as the first Siri Suggestion.
#   chat:      the Keybots panel open under a Messages thread. Both halves are real captures:
#              the thread from keyboard-hold (an empty field, some blank chat removed), the panel
#              from keyboard-bots-mainnet-dark (cut below the Spotlight search bar).
node "$here/patches.mjs"
ffmpeg -loglevel error -y -i "$src/keyboard-bots-mainnet-dark.png" -i "$here/out/patch-icon.png" -i "$here/out/patch-label.png" \
  -filter_complex "[0][1]overlay=118:380[a];[a][2]overlay=111:594,scale=630:-2" -q:v 3 "$out/hero-spotlight.jpg"
ffmpeg -loglevel error -y -i "$src/keyboard-hold.png" -i "$src/keyboard-bots-mainnet-dark.png" \
  -i "$here/out/patch-back.png" -i "$here/out/patch-input.png" -filter_complex \
  "[0][2]overlay=18:112[h];[h][3]overlay=240:1506[h2];[h2]split[a][b];[a]crop=1260:800:0:0[t1];[b]crop=1260:712:0:948[t2];[1]crop=1260:1224:0:1512[p];[t1][t2][p]vstack=3,scale=630:-2" \
  -q:v 3 "$out/hero-chat.jpg"
cp "$out/hero-${HERO:-spotlight}.jpg" "$out/hero.jpg"
jpg keyboard-bots-testnet-dark testnet
# The pay screen, with the two patches laid over the old labels.
node "$here/patches.mjs"
ffmpeg -loglevel error -y -i "$src/keyboard-hold.png" -i "$here/out/patch-back.png" -i "$here/out/patch-space.png" \
  -filter_complex "[0][1]overlay=18:112[a];[a][2]overlay=440:2398,scale=630:-2" -q:v 3 "$out/pay.jpg"
jpg app-activity-dark activity
jpg app-spend-limits-lists-dark blocklist
jpg kb-posts-dark calls
jpg kb-review-dark swap
jpg kb-receipt-swapped-light swapped
jpg app-lanes-dark lanes
jpg app-change-limits-dark limits
jpg kb-assist-fix-dark ai
ls -l "$out"
