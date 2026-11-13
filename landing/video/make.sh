#!/usr/bin/env bash
# Joins the intro card, Harshal's screen recording with timed captions, and the end card into one 1080p MP4.
#   ./make.sh recording.mov [airkey-demo.mp4]
#   PRESET=veryfast ./make.sh recording.mov draft.mp4    # a quick draft
# A portrait recording (iPhone) sits on the AIRKEY background with captions to its right;
# a landscape one fills the frame with lower-third captions. Caption times come from beats.json.
set -euo pipefail
cd "$(dirname "$0")"

REC=${1:?usage: ./make.sh recording.mov [out.mp4]}
OUT=${2:-airkey-demo.mp4}
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed (brew install ffmpeg)"; exit 1; }
[ -d node_modules/@resvg ] || npm install --silent
node render.mjs >/dev/null

read -r W H < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$REC" | tr 'x' ' ')
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$REC")
HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$REC" | head -1 || true)
INTRO=$(node -e 'console.log(require("./beats.json").intro.seconds)')
END=$(node -e 'console.log(require("./beats.json").end.seconds)')
BEATS=$(node -e 'require("./beats.json").beats.forEach((b,i)=>console.log(String(i+1).padStart(2,"0"),b.start,b.end))')
TOTAL=$(node -e "console.log(($INTRO+$DUR+$END).toFixed(1))")

if [ "$H" -gt "$W" ]; then LAYOUT=side; else LAYOUT=lower; fi
echo "recording ${W}x${H}, ${DUR}s, layout: $LAYOUT, final length: ${TOTAL}s"
node -e "const t=$TOTAL; if (t<120||t>150) console.log('note: the hackathon video should be 2:00 to 2:30; this one is '+t+'s')"

inputs=(
  -loop 1 -framerate 30 -t "$INTRO" -i build/intro.png
  -i "$REC"
  -loop 1 -framerate 30 -t "$END" -i build/end.png
  -loop 1 -framerate 30 -t "$DUR" -i build/bg.png
  -i build/bug.png
  -f lavfi -t "$TOTAL" -i anullsrc=r=48000:cl=stereo
)
idx=6
caps=()
while read -r n s e; do
  inputs+=(-i "build/cap-$LAYOUT-$n.png")
  caps+=("$idx $s $e")
  idx=$((idx + 1))
done <<<"$BEATS"

norm="fps=30,format=yuv420p,setsar=1"
f="[0:v]scale=1920:1080,$norm,fade=t=out:st=$(node -e "console.log($INTRO-0.3)"):d=0.3[iv];"
f+="[2:v]scale=1920:1080,$norm,fade=t=in:st=0:d=0.4[ev];"
if [ "$LAYOUT" = side ]; then
  f+="[1:v]scale=-2:960,setsar=1[r];[3:v][r]overlay=x=300:y=60:shortest=1[b0];"
else
  f+="[1:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x050505,setsar=1[b0];"
fi
f+="[b0][4:v]overlay=0:0[c0];"
k=0
for c in "${caps[@]}"; do
  read -r i s e <<<"$c"
  f+="[c$k][$i:v]overlay=0:0:enable='between(t,$s,$e)'[c$((k + 1))];"
  k=$((k + 1))
done
f+="[c$k]$norm[mv];"
f+="[5:a]asplit=3[a0][a1][a2];[a0]atrim=0:$INTRO,asetpts=N/SR/TB[ia];[a2]atrim=0:$END,asetpts=N/SR/TB[ea];"
if [ -n "$HAS_AUDIO" ]; then
  f+="[1:a]aresample=48000,aformat=channel_layouts=stereo,apad,atrim=0:$DUR,asetpts=N/SR/TB[ma];[a1]anullsink;"
else
  f+="[a1]atrim=0:$DUR,asetpts=N/SR/TB[ma];"
fi
f+="[iv][ia][mv][ma][ev][ea]concat=n=3:v=1:a=1[v][a]"

ffmpeg -hide_banner -loglevel error -stats -y "${inputs[@]}" -filter_complex "$f" -map "[v]" -map "[a]" \
  -c:v libx264 -preset "${PRESET:-medium}" -crf 18 -pix_fmt yuv420p -r 30 -c:a aac -b:a 160k -movflags +faststart "$OUT"

echo "wrote $OUT ($(node -e "console.log((require('fs').statSync('$OUT').size/1e6).toFixed(1))") MB)"
