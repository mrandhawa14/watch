#!/usr/bin/env bash
# Convert a video to a browser-friendly MP4 (H.264 + AAC, faststart).
# Auto-detects codec (fast remux when it can) and BURNS IN subtitles if present.
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
scodec=$(ffprobe -v error -select_streams s:0 -show_entries stream=codec_name -of csv=p=0 "$SRC" | head -1)
echo "Detected:  video=${vcodec:-none}   audio=${acodec:-none}   subs=${scodec:-none}"

# --- audio (same for every path) ---
if [ "$acodec" = "aac" ]; then
  aargs=(-c:a copy);          echo "  audio  -> copy"
elif [ -z "$acodec" ]; then
  aargs=(-an);                echo "  audio  -> none"
else
  aargs=(-c:a aac -b:a 192k); echo "  audio  -> convert ${acodec} to AAC"
fi
echo ""

if [ -n "$scodec" ]; then
  # Burning subtitles paints them onto the frames, so the video MUST be re-encoded.
  echo "  subs   -> burning in first track (${scodec}); this re-encodes the video (takes a while)..."
  VENC=(-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p)
  case "$scodec" in
    hdmv_pgs_subtitle|dvd_subtitle|dvb_subtitle|xsub)
      # Image-based subs: overlay the subtitle stream onto the video.
      ffmpeg -hide_banner -i "$SRC" \
        -filter_complex "[0:v:0][0:s:0]overlay[v]" -map "[v]" -map 0:a:0? \
        "${VENC[@]}" "${aargs[@]}" -movflags +faststart "$OUT"
      ;;
    *)
      # Text subs (subrip/ass/…): render via the subtitles filter. Extract to a temp
      # file with a plain name first so the filter path has no spaces/quotes to escape.
      SUBDIR="$(mktemp -d)"
      if ffmpeg -y -hide_banner -loglevel error -i "$SRC" -map 0:s:0 "$SUBDIR/subs.ass" 2>/dev/null; then
        SUBNAME="subs.ass"
      else
        ffmpeg -y -hide_banner -loglevel error -i "$SRC" -map 0:s:0 "$SUBDIR/subs.srt"
        SUBNAME="subs.srt"
      fi
      SRCABS="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
      OUTABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
      ( cd "$SUBDIR" && ffmpeg -hide_banner -i "$SRCABS" \
          -vf "subtitles=$SUBNAME" "${VENC[@]}" "${aargs[@]}" -movflags +faststart "$OUTABS" )
      rm -rf "$SUBDIR"
      ;;
  esac
else
  # No subtitles: keep the fast path — copy H.264, re-encode only if needed.
  if [ "$vcodec" = "h264" ]; then
    vargs=(-c:v copy);                                           echo "  video  -> copy (instant, no quality loss)"
  else
    vargs=(-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p); echo "  video  -> re-encode to H.264"
  fi
  echo ""
  ffmpeg -hide_banner -i "$SRC" "${vargs[@]}" "${aargs[@]}" -movflags +faststart "$OUT"
fi

echo ""
echo "Done -> $OUT"
echo "Now publish it:  ./add-video-r2.sh \"$OUT\""
