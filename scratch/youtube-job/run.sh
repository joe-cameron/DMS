#!/usr/bin/env bash
# Transcribe + frame-align a downloaded YouTube video.
#
# Inputs (drop into ./input/):
#   video.mp4        - the downloaded video
#   video.en.srt     - SRT transcript (yt-dlp auto-caps or whisper output)
#
# Outputs (./output/):
#   transcript.json  - parsed cues
#   scenes.txt       - scene-change timestamps (seconds)
#   aligned.md       - markdown report: timestamp + caption + frame image
#   ./frames/*.jpg   - one frame per scene change
#
# Tunable:
#   SCENE_THRESHOLD - ffmpeg select=gt(scene,X). Default 0.30. Lower = more frames.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

VIDEO="input/video.mp4"
SRT="input/video.en.srt"
SCENE_THRESHOLD="${SCENE_THRESHOLD:-0.30}"

[[ -f "$VIDEO" ]] || { echo "missing $VIDEO" >&2; exit 1; }
[[ -f "$SRT"   ]] || { echo "missing $SRT"   >&2; exit 1; }

rm -rf frames output
mkdir -p frames output

echo "[1/4] detecting scene changes (threshold=$SCENE_THRESHOLD)..."
ffmpeg -hide_banner -loglevel error -i "$VIDEO" \
  -vf "select='gt(scene,${SCENE_THRESHOLD})',showinfo" \
  -vsync vfr -f null - 2> output/showinfo.log
grep -oP 'pts_time:\K[0-9.]+' output/showinfo.log > output/scenes.txt || true
# Always include t=0 so we have a frame even on still videos.
if ! grep -q "^0" output/scenes.txt; then
  printf "0.000000\n%s" "$(cat output/scenes.txt)" > output/scenes.txt.tmp
  mv output/scenes.txt.tmp output/scenes.txt
fi
N_SCENES=$(wc -l < output/scenes.txt)
echo "    found $N_SCENES scene boundaries"

echo "[2/4] extracting frames..."
i=0
while read -r ts; do
  [[ -z "$ts" ]] && continue
  i=$((i+1))
  out=$(printf "frames/scene_%03d_t%07.2f.jpg" "$i" "$ts")
  ffmpeg -hide_banner -loglevel error -ss "$ts" -i "$VIDEO" \
    -frames:v 1 -q:v 3 "$out"
done < output/scenes.txt
echo "    wrote $i frames to ./frames/"

echo "[3/4] parsing SRT + aligning..."
python3 align.py
echo "[4/4] done. See output/aligned.md"
