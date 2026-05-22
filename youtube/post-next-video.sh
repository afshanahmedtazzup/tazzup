#!/usr/bin/env bash
# Tazzup daily YouTube poster.
# Reads ~/projects/tazzup/youtube/post-queue.json, picks the next "pending"
# entry, builds the per-video metaJSON, calls youtubeuploader (which refreshes
# the OAuth access_token transparently using the stored refresh_token), and
# on success flips status to "posted" with a timestamp + the returned videoId.
#
# Triggered daily by ~/Library/LaunchAgents/com.tazzup.daily-video-post.plist
# at 09:00 local OR via the n8n workflow `tazzup-daily-video-post`.
#
# Logs to ~/projects/tazzup/youtube/post-log.log

set -uo pipefail

QUEUE=/Users/tariknaeem/projects/tazzup/youtube/post-queue.json
LOG=/Users/tariknaeem/projects/tazzup/youtube/post-log.log
SECRETS=/Users/tariknaeem/.config/youtubeuploader/client_secrets.json
TOKEN=/Users/tariknaeem/.config/youtubeuploader/request.token
META_DIR=/Users/tariknaeem/projects/tazzup/youtube/manifests
UPLOADER=/opt/homebrew/bin/youtubeuploader
FFMPEG=/opt/homebrew/bin/ffmpeg

mkdir -p "$META_DIR"

ts() { date -u "+%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

log "========== post-next-video starting =========="

for tool in jq "$UPLOADER" "$FFMPEG"; do
  if ! command -v "$tool" >/dev/null 2>&1 && [[ ! -x "$tool" ]]; then
    log "ERROR: missing tool $tool"
    exit 1
  fi
done

if [[ ! -f "$SECRETS" || ! -f "$TOKEN" ]]; then
  log "ERROR: youtubeuploader auth files missing"
  exit 1
fi

NEXT=$(jq -c '.queue[] | select(.status == "pending")' "$QUEUE" | head -1)
if [[ -z "$NEXT" ]]; then
  log "Queue empty — nothing to post."
  exit 0
fi

ID=$(echo "$NEXT" | jq -r .id)
VIDEO=$(echo "$NEXT" | jq -r .videoPath)
THUMB=$(echo "$NEXT" | jq -r .thumbPath)
TITLE=$(echo "$NEXT" | jq -r .title)
DESC=$(echo "$NEXT" | jq -r .description)
TAGS=$(echo "$NEXT" | jq -r .tags)

log "Posting $ID — $TITLE"

if [[ ! -f "$VIDEO" ]]; then
  log "ERROR: video file missing: $VIDEO"
  TMP=$(mktemp)
  jq --arg id "$ID" --arg ts "$(ts)" --arg err "video missing" '
    (.queue[] | select(.id == $id) | .status) = "failed" |
    (.queue[] | select(.id == $id) | .lastError) = $err |
    (.queue[] | select(.id == $id) | .lastTriedAt) = $ts
  ' "$QUEUE" > "$TMP" && mv "$TMP" "$QUEUE"
  exit 1
fi

# Build the youtubeuploader metaJSON. Privacy starts as `unlisted` for the
# first 24 hours so any catastrophic miss can be fixed before it's indexed;
# you can change this via env DEFAULT_PRIVACY=public if you want to skip the
# soft-launch window.
PRIVACY="${DEFAULT_PRIVACY:-unlisted}"
META_FILE="$META_DIR/$ID.upload.json"
# youtubeuploader expects tags as a JSON []string, not a comma-separated string.
TAGS_JSON=$(echo "$TAGS" | jq -R 'split(",") | map(gsub("^ +| +$"; ""))')
jq -n \
  --arg title "$TITLE" \
  --arg desc "$DESC" \
  --argjson tags "$TAGS_JSON" \
  --arg privacy "$PRIVACY" '
  {
    title: $title,
    description: $desc,
    tags: $tags,
    privacyStatus: $privacy,
    categoryId: "22",
    playlistTitles: ["Tazzup Family Shorts"],
    language: "en",
    madeForKids: true,
    publishToSubscriptionsFeed: true,
    notifySubscribers: true
  }' > "$META_FILE"

# Auto-resize thumbnail if over YouTube's 2 MB limit.
THUMB_USE="$THUMB"
if [[ -f "$THUMB" ]]; then
  SIZE=$(stat -f%z "$THUMB" 2>/dev/null || stat -c%s "$THUMB" 2>/dev/null)
  if [[ "$SIZE" -gt 2000000 ]]; then
    THUMB_USE="/tmp/$ID-thumb.jpg"
    "$FFMPEG" -y -loglevel error -i "$THUMB" \
      -vf "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720" \
      -q:v 4 "$THUMB_USE"
  fi
fi

# Upload. youtubeuploader will refresh the access_token via refresh_token if
# the cached access_token is expired.
log "→ youtubeuploader -filename $VIDEO -metaJSON $META_FILE"
OUTPUT=$("$UPLOADER" \
  -secrets "$SECRETS" \
  -cache "$TOKEN" \
  -filename "$VIDEO" \
  -metaJSON "$META_FILE" \
  -thumbnail "$THUMB_USE" 2>&1 || true)
echo "$OUTPUT" | tee -a "$LOG"

# youtubeuploader prints `Video ID: <id>` on success.
VIDEO_ID=$(echo "$OUTPUT" | grep -Eo 'Video ID: [^ ]+' | awk '{print $3}' | head -1)

TMP=$(mktemp)
if [[ -n "$VIDEO_ID" ]]; then
  YT_URL="https://youtu.be/$VIDEO_ID"
  log "✅ posted $ID as $VIDEO_ID → $YT_URL"
  jq --arg id "$ID" --arg ts "$(ts)" --arg vid "$VIDEO_ID" --arg url "$YT_URL" '
    (.queue[] | select(.id == $id) | .status) = "posted" |
    (.queue[] | select(.id == $id) | .postedAt) = $ts |
    (.queue[] | select(.id == $id) | .youtubeId) = $vid |
    (.queue[] | select(.id == $id) | .youtubeUrl) = $url |
    .history += [{"id": $id, "youtubeId": $vid, "url": $url, "postedAt": $ts}]
  ' "$QUEUE" > "$TMP" && mv "$TMP" "$QUEUE"
  exit 0
else
  log "❌ upload returned no Video ID — marking failed"
  jq --arg id "$ID" --arg ts "$(ts)" --arg err "no video id returned" '
    (.queue[] | select(.id == $id) | .status) = "failed" |
    (.queue[] | select(.id == $id) | .lastError) = $err |
    (.queue[] | select(.id == $id) | .lastTriedAt) = $ts
  ' "$QUEUE" > "$TMP" && mv "$TMP" "$QUEUE"
  exit 1
fi
