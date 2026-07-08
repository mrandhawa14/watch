#!/usr/bin/env bash
# Convert any video to a browser-friendly MP4 (H.264 + AAC, faststart).
# Auto-detects the codec: instant remux when it can, full re-encode when it must.
# Usage: ./to-mp4.sh /path/to/input.mkv
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "Usage: ./to-mp4.sh /path/to/input.mkv"
  [ -n "$SRC" ] && echo "File not found: $SRC"
  exit 1
fi
command -v ffmpeg  >/dev/null || { echo "ffmpeg not found";  exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found"; exit 1; }

OUT="${SRC%.*}.mp4"
if [ -e "$OUT" ]; then
  echo "Output already exists: $OUT — move/delete it first, then re-run."
  exit 1
fi

vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$SRC" | head -1)
acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$SRC" | head -1)
echo "Detected:  video=${vcodec:-none}   audio=${acodec:-none}"

if [ "$vcodec" = "h264" ]; then
  vargs=(-c:v copy)
  echo "  video  -> copy (instant, no quality loss)"
else
  vargs=(-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p)
  echo "  video  -> re-encode to H.264 (this one takes a while)"
fi

if [ "$acodec" = "aac" ]; then
  aargs=(-c:a copy);        echo "  audio  -> copy"
elif [ -z "$acodec" ]; then
  aargs=(-an);              echo "  audio  -> none"
else
  aargs=(-c:a aac -b:a 192k); echo "  audio  -> convert ${acodec} to AAC"
fi

echo ""
ffmpeg -hide_banner -i "$SRC" "${vargs[@]}" "${aargs[@]}" -movflags +faststart "$OUT"
echo ""
echo "Done -> $OUT"
echo "Now publish it:  ./add-video.sh \"$OUT\""
