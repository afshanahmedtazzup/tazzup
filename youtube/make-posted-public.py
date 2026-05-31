#!/usr/bin/env python3
"""Flip every already-posted Tazzup video to public.

youtubeuploader can only create videos, not update them, so the videos that
were uploaded while the pipeline defaulted to `unlisted` stay unlisted forever
unless we call videos.update directly. This reads the same OAuth credentials
youtubeuploader uses, refreshes the access token, and sets privacyStatus=public
on each posted video in the queue.

Run after re-authing (so request.token holds a live refresh_token):
    python3 ~/projects/tazzup/youtube/make-posted-public.py
"""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

SECRETS = Path.home() / ".config/youtubeuploader/client_secrets.json"
TOKEN = Path.home() / ".config/youtubeuploader/request.token"
QUEUE = Path.home() / "projects/tazzup/youtube/post-queue.json"


def load_client():
    data = json.loads(SECRETS.read_text())
    node = data[next(iter(data))]  # "installed" or "web"
    return node["client_id"], node["client_secret"]


def access_token():
    client_id, client_secret = load_client()
    refresh = json.loads(TOKEN.read_text())["refresh_token"]
    body = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
    with urllib.request.urlopen(req) as r:
        return json.load(r)["access_token"]


def set_public(video_id, token):
    payload = json.dumps({
        "id": video_id,
        "status": {"privacyStatus": "public"},
    }).encode()
    url = "https://www.googleapis.com/youtube/v3/videos?part=status"
    req = urllib.request.Request(url, data=payload, method="PUT")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        return json.load(r)["status"]["privacyStatus"]


def main():
    queue = json.loads(QUEUE.read_text())
    posted = [e for e in queue["queue"] if e.get("status") == "posted" and e.get("youtubeId")]
    if not posted:
        print("No posted videos with a youtubeId found.")
        return
    token = access_token()
    for e in posted:
        try:
            status = set_public(e["youtubeId"], token)
            print(f"✅ {e['id']} ({e['youtubeId']}) -> {status}")
        except urllib.error.HTTPError as err:
            print(f"❌ {e['id']} ({e['youtubeId']}) -> {err.code} {err.read().decode()[:200]}", file=sys.stderr)


if __name__ == "__main__":
    main()
