# Jarvis Assistant (macOS)

A menu-bar voice assistant for your Mac: say "**Jarvis, ...**" out loud, it transcribes your
command on-device, sends it to Claude (via the Anthropic API) with a small set of tools for
actually doing things on your Mac, and speaks the reply back. Inspired by Alexa/Siri/Jarvis —
built as a personal hobby tool, not a polished shrink-wrapped product.

**This was written in a Linux sandbox with no Xcode/macOS toolchain available, so it has not
been compiled or run.** The code is written carefully against documented Apple APIs, but expect
to fix a handful of small compile errors on your first `swift build` on your actual Mac.

## What it is / isn't

- It is: a background menu-bar app, wake-word activated, that turns spoken commands into actions
  (open apps, control apps via AppleScript, read/write files in a scratch folder, optionally run
  shell commands) using Claude as the reasoning engine.
- It isn't: sandboxed, notarized, or reviewed by anyone but Claude. It runs arbitrary AppleScript
  (and optionally arbitrary shell commands) based on speech-to-text of whatever your microphone
  picks up. Don't run it on a shared/multi-user Mac, and be aware anyone speaking near your Mac
  could trigger it.

## Requirements

- macOS 13 (Ventura) or later.
- Xcode Command Line Tools (`xcode-select --install`) — gives you `swift`/`swiftc`. A full Xcode
  install also works and lets you open this as a Swift Package project directly.
- An Anthropic API key from https://console.anthropic.com.

## Build

```bash
cd macos-voice-assistant
swift build -c release
```

Or use the install script, which also copies the binary to a stable path
(`~/Applications/JarvisAssistant/JarvisAssistant`) so the in-app "Launch at Login" toggle has a
permanent location to point at:

```bash
./Scripts/install.sh
```

## First run

1. Run the binary directly from Terminal once (`.build/release/JarvisAssistant`, or the installed
   copy). A waveform icon should appear in your menu bar.
2. macOS will prompt for **Microphone** and **Speech Recognition** access — approve both
   (System Settings > Privacy & Security if you miss the prompt).
3. Click the menu bar icon > **Set Anthropic API Key…** and paste your key. It's stored in the
   macOS Keychain, never written to disk in plaintext.
4. **Before you rely on it**, open `~/Library/Application Support/JarvisAssistant/config.json` and
   double check the `model` field. Claude Code's short internal model names (like
   `claude-sonnet-5`) don't always match the exact string the public Anthropic Messages API
   expects — confirm the current one at
   https://docs.anthropic.com/en/docs/about-claude/models and edit the config if needed.
5. Say "**Jarvis, ...**" followed by your request. The menu bar icon changes as it moves through
   states:
   - waveform → idle, listening for the wake word
   - filled mic → capturing your command
   - ellipsis → thinking (talking to Claude, possibly running tools)
   - speaker → speaking the reply out loud

## Config file

`~/Library/Application Support/JarvisAssistant/config.json`:

| Field | Meaning |
|---|---|
| `model` | Anthropic model ID to call. |
| `wakeWord` | Word/phrase that activates command capture (default `"jarvis"`). |
| `voiceIdentifier` | `AVSpeechSynthesisVoice` identifier to use, or `null` for the system default English voice. |
| `speechRate` | TTS speaking rate (`AVSpeechUtterance.rate`, roughly 0.0–1.0). |
| `allowShellCommands` | Off by default. Lets Claude run arbitrary zsh commands (see Safety below). |
| `allowAppleScript` | On by default. Lets Claude control Mac apps/system settings via AppleScript. |
| `allowOpenApps` | On by default. Lets Claude open apps and URLs. |
| `allowFileAccess` | On by default. Lets Claude read/write files, scoped to `workspaceDirectory`. |
| `workspaceDirectory` | Folder Claude's file tools are confined to. |
| `maxToolIterations` | Cap on tool-call round-trips per spoken command, so a confused loop can't run forever. |
| `launchAtLogin` | Mirrors the menu bar toggle; installs/removes a LaunchAgent. |

Restart the app after hand-editing the config file.

## Launch at login / background

Toggle **Launch at Login** from the menu bar icon. This installs a `launchd` LaunchAgent
(`~/Library/LaunchAgents/com.jarvis.assistant.plist`) pointed at the currently running binary's
path, so build/run it from its final install location first (see `Scripts/install.sh`).

**Important:** `launchd` starts it headlessly at login, before you're at a Terminal — it can't
show the Microphone/Speech Recognition permission prompts at that point. Grant both permissions
manually first (step 2 above) before enabling Launch at Login.

## Safety notes

- **AppleScript control is on by default** — that's what makes it feel like Jarvis (volume,
  Reminders, Calendar, opening apps, etc.), but it also means a speech-recognition
  misunderstanding could trigger an unintended action. Check **Open Log** in the menu if
  something unexpected happens — every tool call is logged before it runs.
- **Raw shell command execution is off by default** and must be explicitly enabled from the menu.
  Even when enabled, a denylist blocks obviously destructive patterns (`rm -rf /`, `mkfs`, `dd`,
  `shutdown`, piping curl into a shell, etc.) — that denylist is a safety net, not a security
  boundary. Only enable it if you're comfortable with that.
- File tools are confined to `workspaceDirectory` (default `~/JarvisAssistant/workspace`); paths
  that would escape it are rejected.
- There's no voice-based confirmation step before a tool runs — by design, since a hands-free
  assistant that asks "are you sure?" before every action defeats the point. If you want a
  higher-friction/lower-blast-radius setup, turn off `allowShellCommands` and `allowAppleScript`
  and keep it to `open_application`/`open_url`/file tools only.

## Known limitations

- Wake-word detection is substring matching on live on-device transcripts, not a dedicated
  wake-word model — it can occasionally mis-trigger on "jarvis" appearing in unrelated speech, or
  miss a mumbled one.
- No barge-in: you can't interrupt it mid-reply by talking over it.
- Single wake word, single language (`en-US`) recognizer, configured in `SpeechEngine.swift`.
- Tool calls execute immediately once Claude decides to make them — no per-call confirmation UI.

## Uninstall

Menu bar icon > **Launch at Login** (turn off) removes the LaunchAgent, then **Quit Jarvis**.
Delete `~/Applications/JarvisAssistant`, `~/Library/Application Support/JarvisAssistant`, and
`~/Library/Logs/JarvisAssistant` to remove all state.
