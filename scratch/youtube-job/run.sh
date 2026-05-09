#!/usr/bin/env bash
# Transcribe + frame-align downloaded YouTube video(s).
#
# Layout (drop into input/<videoId>/):
#   input/<id>/video.mp4    - downloaded video
#   input/<id>/video.en.srt - SRT transcript (yt-dlp auto-caps or whisper)
#
# Outputs:
#   output/<id>/transcript.json
#   output/<id>/scenes.txt
#   output/<id>/aligned.md
#   frames/<id>/*.jpg
#
# Usage:
#   bash run.sh                  # process every input/<id>/ folder
#   bash run.sh bCljOfCH8Ms      # process just one
#
# Tunable:
#   SCENE_THRESHOLD - ffmpeg select=gt(scene,X). Default 0.30. Lower = more frames.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SCENE_THRESHOLD="${SCENE_THRESHOLD:-0.30}"

process_one() {
  local id="$1"
  local video="input/${id}/video.mp4"
  local srt="input/${id}/video.en.srt"

  [[ -f "$video" ]] || { echo "[$id] missing $video, skipping" >&2; return; }
  [[ -f "$srt"   ]] || { echo "[$id] missing $srt, skipping"   >&2; return; }

  echo "=== [$id] ==="
  rm -rf "frames/${id}" "output/${id}"
  mkdir -p "frames/${id}" "output/${id}"

  echo "[1/3] [$id] detecting scene changes (threshold=$SCENE_THRESHOLD)..."
  ffmpeg -hide_banner -loglevel error -i "$video" \
    -vf "select='gt(scene,${SCENE_THRESHOLD})',showinfo" \
    -vsync vfr -f null - 2> "output/${id}/showinfo.log"
  grep -oP 'pts_time:\K[0-9.]+' "output/${id}/showinfo.log" > "output/${id}/scenes.txt" || true
  if ! grep -q "^0" "output/${id}/scenes.txt"; then
    printf "0.000000\n%s" "$(cat "output/${id}/scenes.txt")" > "output/${id}/scenes.txt.tmp"
    mv "output/${id}/scenes.txt.tmp" "output/${id}/scenes.txt"
  fi
  local n
  n=$(wc -l < "output/${id}/scenes.txt")
  echo "    [$id] found $n scene boundaries"

  echo "[2/3] [$id] extracting frames..."
  local i=0
  while read -r ts; do
    [[ -z "$ts" ]] && continue
    i=$((i+1))
    out=$(printf "frames/%s/scene_%03d_t%07.2f.jpg" "$id" "$i" "$ts")
    ffmpeg -hide_banner -loglevel error -ss "$ts" -i "$video" \
      -frames:v 1 -q:v 3 "$out"
  done < "output/${id}/scenes.txt"
  echo "    [$id] wrote $i frames"

  echo "[3/3] [$id] aligning..."
  python3 align.py "$id"
}

if [[ $# -gt 0 ]]; then
  for id in "$@"; do
    process_one "$id"
  done
else
  shopt -s nullglob
  any=0
  for d in input/*/; do
    id="$(basename "$d")"
    [[ "$id" == ".gitkeep" ]] && continue
    process_one "$id"
    any=1
  done
  [[ $any -eq 0 ]] && echo "no input/<id>/ folders found" >&2
fi
echo "done."
