# Jarvis — a voice assistant for macOS, powered by Claude

Jarvis listens for **“Hey Jarvis”**, transcribes what you say, answers with
Claude (searching the web when needed), can **control your Mac**, and speaks the
answer back — all through a floating, Siri-class animated orb.

This is a ground-up rewrite (v2) focused on three things: **catching audio
properly**, **feeling instant**, and **looking good**.

```
  Hey Jarvis ─▶ 🎙 capture ─▶ 🗣 wake word ─▶ ⏹ endpoint ─▶ ✍️ Whisper
        ▲                                                        │
        └── 🔊 speak ◀── 🌀 stream ◀── 🧠 Claude + tools + web ◀─┘
```

## What’s new vs. the old version

| Area | Old | New |
|---|---|---|
| **Audio capture** | fixed-length record, clipped first word | always-on 16 kHz stream with a 600 ms **pre-roll** buffer, self-healing device recovery |
| **Wake word** | none / naive | **openWakeWord “hey jarvis”** running fully on-device |
| **Endpointing** | fixed timeout | **WebRTC-VAD** — stops when *you* stop talking |
| **Transcription** | cloud round-trip | **faster-whisper** locally (offline, private, sub-second) |
| **Replies** | wait for the whole answer | **streamed** and spoken **sentence-by-sentence** — starts talking immediately |
| **Barge-in** | none | say “Hey Jarvis” or tap the orb to **cut Jarvis off** mid-answer |
| **Mac control** | none | open apps, set volume/brightness, media keys, type, screenshots, run shell — via Claude tools |
| **Internet** | limited | Claude **web search** for complete, current answers |
| **Offline** | fails | **learns from Claude** — caches answers and replies from them when offline; instant local skills for time, timers, math, volume, apps |
| **UI** | poor | a fluid, audio-reactive, state-colored **orb** (the thing you asked to fix) |

## Design goals, and how each is met

**“Catch audio properly.”** The capture layer keeps a rolling pre-roll buffer,
so recording begins ~600 ms *before* the wake word fires — the first syllable is
never lost. WebRTC-VAD decides when you’ve finished, with a trailing-silence
window tuned like Google Assistant’s, plus a no-speech timeout so it never hangs.
Whisper (`base.en` by default) runs locally for fast, private transcription.

**“Complete answers using the Claude platform for internet things.”** The brain
streams from **Claude Opus 4.8** with the **`web_search`** server tool enabled,
so current events, prices, and facts come back complete and cited-current.

**“Learn from Claude so it works offline.”** Every web-answered factual question
is cached with a lightweight character-n-gram TF-IDF index. Ask something similar
later while offline and Jarvis answers from what it learned — no network needed.
Everyday commands (time, timers, arithmetic, volume, launching apps, remembered
facts) are handled by **instant on-device skills**, online or off.

**“Control my laptop fully.”** Claude is given real Mac tools — `open_app`,
`open_url`, `set_volume`, `set_brightness`, `media_control`, `system_action`
(lock/sleep/screenshot/notify), `type_text`, `get_screen_text`, and `run_shell`.
Ask it to *do* things, not just describe them.

**“Make it visually appealing.”** The orb is a real-time canvas render: layered
morphing fluid blobs, a glossy specular core, an audio-reactive waveform ring
while listening/speaking, orbiting dots while thinking, and smooth color
transitions per state (blue idle → teal listening → violet thinking → amber
speaking). It’s frameless, transparent, always-on-top, and draggable.

## Install

```bash
cd jarvis
./install.sh
export ANTHROPIC_API_KEY=sk-ant-...      # for internet answers
source .venv/bin/activate
python -m jarvis
```

`install.sh` sets up a virtualenv, installs PortAudio + Python deps, downloads
the wake-word model, and optionally installs a LaunchAgent to start Jarvis at
login.

### First-run permissions (macOS)

Grant these in **System Settings → Privacy & Security**, or Jarvis can’t hear or
act:

- **Microphone** — for the terminal/app running Jarvis (wake word + speech).
- **Accessibility** — for the global hotkey, `type_text`, media keys, brightness.
- **Automation** — allow control of the apps you ask Jarvis to drive.

## Using it

- Say **“Hey Jarvis”**, then your request. Or **tap the orb**, or press the
  hotkey (default **⌥Space**).
- After a reply Jarvis keeps listening for a few seconds, so you can follow up
  (“…and what about tomorrow?”) without the wake word.
- Interrupt any time by saying “Hey Jarvis” or tapping the orb.

Examples:

> “Hey Jarvis, what’s the weather in Mumbai this weekend?” *(web search)*
> “Open Spotify and play.” *(Mac control)*
> “Set the volume to 30 and turn the brightness down.” *(instant, local)*
> “Set a timer for 10 minutes.” *(instant, local)*
> “Remember that my flight is at 6pm.” … later: “What’s my flight?” *(memory)*
> “What’s 15% of 240?” *(instant, offline)*

## Configuration

Everything lives in `~/.jarvis/config.json` (created on first run). Highlights:

| Key | Default | Meaning |
|---|---|---|
| `model` | `claude-opus-4-8` | Claude model for the brain |
| `effort` | `low` | reasoning effort — `low` keeps voice snappy; raise for harder tasks |
| `web_search` | `true` | let Claude search the internet |
| `whisper_model` | `base.en` | `tiny.en`/`base.en`/`small.en` — bigger = more accurate, slower |
| `voice` | `""` | macOS voice name; set a Premium/Siri voice for a big quality jump |
| `wake_word_enabled` | `true` | “Hey Jarvis” always-on listening |
| `follow_up_s` | `6.0` | seconds Jarvis keeps listening after a reply (0 = off) |
| `allow_shell` | `true` | allow the `run_shell` tool |
| `offline_only_cache` | `true` | `true`: cache used only offline; `false`: cache-first always |

Run `python -m jarvis --devices` to list microphones (set `input_device`), or
`python -m jarvis --no-ui` for a headless/voice-only session.

## How it fits together

```
jarvis/
  __main__.py         entry point + threading model
  assistant.py        the state machine (idle→listen→think→speak, barge-in, follow-up)
  config.py           ~/.jarvis/config.json
  events.py           in-process event bus (assistant → UI)
  audio/
    capture.py        always-on stream + pre-roll ring buffer + device recovery
    wakeword.py       openWakeWord "hey jarvis"
    vad.py            WebRTC-VAD endpointing
    chime.py          system earcons
  stt/transcriber.py  faster-whisper (local, offline)
  tts/speaker.py      sentence-queued macOS `say` with instant barge-in
  brain/
    claude_client.py  Claude streaming + web search + Mac tools + offline fallback
    mac_tools.py      the tools Claude uses to control the Mac
    offline_skills.py instant local answers (time, timers, math, volume, apps, memory)
    memory.py         SQLite: history, facts, and the offline knowledge cache
  ui/
    orb.html          the animated Siri-class orb (canvas)
    server.py         websocket bridge (state/level/captions ↔ orb)
    window.py         frameless, transparent, always-on-top pywebview window
```

## Privacy

Wake-word detection and speech-to-text run **entirely on your Mac**. Audio is
only ever turned into text locally; that text is sent to Claude **only** when you
ask something that needs it. The offline cache means repeat questions can be
answered without any network at all.

## Troubleshooting

- **No wake word** → the model download may have been skipped; re-run
  `python -m jarvis` (it self-downloads), or just use ⌥Space / tap-to-talk.
- **Can’t hear me** → grant Microphone permission; check the right device with
  `--devices` and set `input_device`.
- **Mac control does nothing** → grant Accessibility + Automation permissions.
- **No internet answers** → set `ANTHROPIC_API_KEY`. Offline skills still work.
