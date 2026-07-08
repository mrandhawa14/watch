#!/usr/bin/env bash
# Upload a video to Cloudflare R2 (serves correct video/mp4 + range, so it plays
# on iPhones), then point the player at it. Handles large files via multipart.
# Usage: ./add-video-r2.sh /path/to/video.mp4
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ]; then echo "Usage: ./add-video-r2.sh /path/to/video.mp4"; exit 1; fi
if [ ! -f "$SRC" ]; then echo "File not found: $SRC"; exit 1; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run this from inside the stream-share repo folder."; exit 1
fi
command -v rclone >/dev/null || { echo "rclone not installed. Run:  brew install rclone"; exit 1; }

CONF=".r2.env"
if [ ! -f "$CONF" ]; then
  echo "Missing $CONF — copy .r2.env.example to .r2.env and fill it in."; exit 1
fi
set -a; . "./$CONF"; set +a
for v in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_BASE; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || { echo "Missing $v in .r2.env"; exit 1; }
done

base="$(basename "$SRC")"
safe="$(printf '%s' "$base" | tr ' ' '.' | tr -cd '[:alnum:]._-')"; [ -z "$safe" ] && safe="video.mp4"

# inline rclone remote "R2" from the env file (no interactive rclone config needed)
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export RCLONE_CONFIG_R2_ACL=private
export RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true

echo "Uploading \"$base\" ($(du -h "$SRC" | cut -f1)) to R2 bucket '$R2_BUCKET' as $safe ..."
rclone copyto "$SRC" "R2:${R2_BUCKET}/${safe}" --progress --s3-chunk-size 64M

URL="${R2_PUBLIC_BASE%/}/${safe}"
echo ""
echo "Public URL: $URL"
echo -n "sanity check: "
curl -sL -o /dev/null -w "http=%{http_code}  type=%{content_type}\n" "$URL" || true
echo "(want: http=200  type=video/mp4)"

python3 - "$URL" <<'PY'
import re, sys
u = sys.argv[1]; s = open("config.js").read()
s = re.sub(r'videoUrl:\s*"[^"]*"', 'videoUrl: "%s"' % u, s); open("config.js", "w").write(s)
PY

git add config.js
git commit -m "Set video URL (R2)" >/dev/null 2>&1 || true
git push >/dev/null 2>&1
echo ""
echo "Done. Send your parents:  https://mrandhawa14.github.io/watch/"
