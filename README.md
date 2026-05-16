# Tazzup

Faceless YouTube content brand. Niche-agnostic. Tagline: **Short. Sharp. Smarter.**

- 🌐 Live site: https://tazzup.tarserv.com
- 📺 Channel: https://www.youtube.com/@tazzup
- 📦 Repo: https://github.com/tariknaeem/tazzup

## What this folder is

A **standalone** project for the Tazzup brand — fully self-contained, no shared code with any other project in `~/projects/`. The landing page lives at `index.html`. Deployment is via GitHub Pages from this repo's `main` branch, with a CNAME at `tazzup.tarserv.com` (subdomain of the user's `tarserv.com` registered with Namecheap).

## What this folder is NOT

- It is not derived from `~/projects/tarserv-landing/`. That's a separate brand belonging to the same user.
- It is not a part of any other project. Each brand stays in its own folder.

## Pipeline integration

The Tazzup channel is fed by:
- `/video-series` skill — daily faceless video generation (`~/.claude/skills/video-series/SKILL.md`)
- Heggsfield MCP — visuals + virality scoring
- macOS `say` (or ElevenLabs later) — voiceover TTS
- `ffmpeg` — stitching
- `youtubeuploader` — programmatic upload
- n8n (Docker on Mac mini, port 5678) — orchestration

Status dashboard: `~/projects/TAZZUP-STATUS.md`
Operating manual: `~/projects/video-monetization-playbook.md`
Zero-human roadmap: `~/projects/zero-human-roadmap.md`

## Local dev

```
cd ~/projects/tazzup
python3 -m http.server 8080
open http://localhost:8080
```

## Deploy

Pushes to `main` auto-deploy via GitHub Pages. CNAME file pins the custom domain.
