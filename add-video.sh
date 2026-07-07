#!/usr/bin/env bash
# Publish a local video so parents can stream it, and wire it into the player.
# Usage: ./add-video.sh /path/to/video.mp4 [release-tag]
set -euo pipefail

SRC="${1:-}"
TAG="${2:-v1}"

if [ -z "$SRC" ]; then
  echo "Usage: ./add-video.sh /path/to/video.mp4 [release-tag]"
  exit 1
fi
if [ ! -f "$SRC" ]; then
  echo "File not found: $SRC"
  exit 1
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run this from inside the stream-share repo folder."
  exit 1
fi

# GitHub Releases caps assets at 2 GB.
bytes=$(stat -f%z "$SRC")
if [ "$bytes" -gt 2147483648 ]; then
  echo "This file is larger than 2 GB, which GitHub Releases won't accept."
  echo "Host it on a large-file service (e.g. Cloudflare R2 — free 10 GB, free egress),"
  echo "then paste that direct URL into config.js as videoUrl and: git commit -am url && git push"
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
OWNER="${REPO%/*}"
NAME="${REPO#*/}"

base="$(basename "$SRC")"
# sanitize to an encode-free filename for a clean URL
safe="$(printf '%s' "$base" | tr ' ' '.' | tr -cd '[:alnum:]._-')"
[ -z "$safe" ] && safe="video.mp4"

echo "Uploading \"$base\" ($(du -h "$SRC" | cut -f1)) to release '$TAG' of $REPO ..."

UP="$SRC"; TMP=""
if [ "$safe" != "$base" ]; then
  TMP="$(dirname "$SRC")/.stream-$safe"
  cp "$SRC" "$TMP"; UP="$TMP"
fi

gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" --title "$TAG" --notes "video host" >/dev/null
gh release upload "$TAG" "$UP" --clobber
[ -n "$TMP" ] && rm -f "$TMP"

URL="https://github.com/$OWNER/$NAME/releases/download/$TAG/$safe"

python3 - "$URL" <<'PY'
import re, sys
url = sys.argv[1]
s = open("config.js").read()
s = re.sub(r'videoUrl:\s*"[^"]*"', 'videoUrl: "%s"' % url, s)
open("config.js", "w").write(s)
PY

git add config.js
git commit -m "Set video URL" >/dev/null 2>&1 || true
git push >/dev/null 2>&1

echo ""
echo "Done. Send your parents this link:"
echo "  https://$OWNER.github.io/$NAME/"
echo "(First deploy can take ~1 minute to go live.)"
