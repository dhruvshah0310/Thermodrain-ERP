---
name: mcp-video-analyzer
description: Use when the user shares a video (YouTube, Instagram, TikTok, Loom, X, Vimeo, a direct URL, or a local file) and wants a transcript, keyframes/screenshots, OCR'd on-screen text, chapters/metadata, or an analysis of a specific moment or time range. Triggers on requests like "summarize this video", "what does this clip say", "pull the text off screen in this recording", "get frames from this Loom", or "transcribe this call recording".
---

# mcp-video-analyzer

Wraps the `video-analyzer` MCP server (https://github.com/guimatheus92/mcp-video-analyzer),
registered as a project MCP server in `.mcp.json`. It downloads/reads a video and extracts
transcripts, keyframes, OCR text, and metadata for use in this conversation.

## Prerequisites

- `yt-dlp` and `ffmpeg` available on PATH (ffmpeg is bundled via `ffmpeg-static`).
- `OPENAI_API_KEY` set if Whisper transcription is needed (otherwise transcripts fall back to
  platform captions/subtitles where available).
- `YTDLP_COOKIES` set (path to a cookies file) for Instagram or age-restricted content.
- `TWELVELABS_API_KEY` is optional, only needed for TwelveLabs Pegasus-generated transcripts.

If a required tool/key is missing, the server degrades gracefully (e.g. skips OCR or
transcription) rather than failing outright — say so to the user rather than treating it as
a hard error.

## Tools

| Tool | Use for |
|---|---|
| `analyze_video` | Full analysis: transcript + frames + OCR + timeline + metadata. Default choice for "summarize/analyze this video." |
| `analyze_videos` | Same as above, batched over multiple sources. |
| `get_transcript` | Transcript only — cheaper/faster when frames/OCR aren't needed. |
| `get_metadata` | Title, description, comments, chapters — no download required. |
| `get_frames` | Keyframes via scene detection or dense sampling, no transcript. |
| `analyze_moment` | Deep-dive on a specific time range within a longer video. |
| `get_frame_at` | A single frame at one timestamp. |
| `get_frame_burst` | Several frames in a narrow time window (e.g. around an on-screen error). |

## Guidance

- Start with `analyze_video` at the default "standard" detail level unless the user only asks
  for one thing (transcript-only, metadata-only, a specific timestamp) — then use the narrower
  tool to avoid unnecessary downloading/processing.
- Use `detail: "brief"` for a quick metadata-only pass, `"detailed"` when the user needs dense
  frame sampling (e.g. reading fast-changing on-screen text or code).
- For "what happens at 2:30" style questions, prefer `analyze_moment` or `get_frame_at` over
  re-running a full analysis.
- Results are cached in-memory for ~10 minutes per source; re-analyzing the same URL shortly
  after is cheap.

## Troubleshooting in this environment

The `video-analyzer` MCP server sometimes fails to spin up at all (deferred tool search finds
nothing) or `npx mcp-video-analyzer@latest analyze ...` silently exits 1 with no error. Two
known causes here, both worked around successfully on 2026-07-16:

- **`ffmpeg-static`'s postinstall fails.** It downloads a prebuilt ffmpeg binary from a GitHub
  releases URL, which this environment's egress policy blocks (403). Fix: install system ffmpeg
  instead (`apt-get update && apt-get install -y --no-install-recommends ffmpeg`, needs a
  fiddly `apt-get update` first if the mirror has drifted), then point the package at it via
  `FFMPEG_BIN=/usr/bin/ffmpeg` — `ffmpeg-static`'s `index.js` reads that env var before trying
  its own bundled binary path.
- **OCR crashes the whole analysis.** `tesseract.js` fetches its language data from a CDN at
  *runtime* (not at npm install time), which is also blocked, and an uncaught worker-thread
  error kills the whole `analyze` process rather than degrading gracefully. Workaround: run
  `analyze` without OCR-dependent detail, or just extract frames directly with system ffmpeg
  (`ffmpeg -i <video> -vf fps=1/N f_%03d.jpg`) and read them with the Read tool — for a UI
  screen-recording (as opposed to natural video), reading frames directly is just as good as
  OCR and doesn't need any network calls at all.
- Also needed: `NODE_USE_ENV_PROXY=1` on any `npm install`/`npx` invocation, since Node's
  built-in `fetch` (used by `ffmpeg-static`'s installer and others) doesn't read `HTTPS_PROXY`
  by default on Node ≥22.21.
- If you need the package installed without its (broken) postinstall script at all:
  `npm install mcp-video-analyzer@latest --ignore-scripts`, then run
  `node node_modules/mcp-video-analyzer/dist/index.js analyze <path> [options]` directly
  (its `dist/cli.js` only exports functions — `dist/index.js` is the real entry point that
  dispatches the `analyze` subcommand).
