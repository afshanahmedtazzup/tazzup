#!/usr/bin/env bash
# Re-authorize the Tazzup YouTube uploader.
#
# The OAuth consent screen for project `tazzup-uploader` is in Testing mode, so
# Google revokes the refresh_token every 7 days. This opens a browser for fresh
# consent and writes a new request.token. youtubeuploader has no auth-only mode,
# so it uploads the bundled tiny test-auth.mp4 as PRIVATE to drive the flow.
#
# DURABLE FIX: publish the consent screen to Production in Google Cloud Console
# (project tazzup-uploader) so tokens stop expiring weekly.
#
# Run interactively (a browser window will open):
#   bash ~/projects/tazzup/youtube/reauth.sh
set -euo pipefail

SECRETS="$HOME/.config/youtubeuploader/client_secrets.json"
TOKEN="$HOME/.config/youtubeuploader/request.token"
TEST="$HOME/.config/youtubeuploader/test-auth.mp4"

[[ -f "$SECRETS" ]] || { echo "missing $SECRETS"; exit 1; }
[[ -f "$TEST" ]] || { echo "missing $TEST"; exit 1; }

if [[ -f "$TOKEN" ]]; then
  mv "$TOKEN" "$TOKEN.revoked.$(date +%s)"
  echo "Backed up stale token."
fi

META="$(mktemp).json"
printf '%s' '{"title":"tazzup auth check","description":"ignore","privacyStatus":"private","categoryId":"22"}' > "$META"

echo "Opening Google consent in your browser…"
youtubeuploader -secrets "$SECRETS" -cache "$TOKEN" -filename "$TEST" -metaJSON "$META"

echo
echo "✅ Auth refreshed → $TOKEN"
echo "   A private 'tazzup auth check' video was created; delete it from YouTube Studio if you want."
echo "   Next: python3 ~/projects/tazzup/youtube/make-posted-public.py   (flips ep01/ep02 to public)"
echo "   Then: bash ~/projects/tazzup/youtube/post-next-video.sh         (drains ep03+ as public)"
