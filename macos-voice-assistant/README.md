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
| `silenceTimeout` | Seconds of silence (once you've started speaking) before a command is finalized. Raise it if you get cut off between words. |
| `commandStartTimeout` | Seconds to wait, after the wake word, for you to begin speaking before giving up. |
| `conversationMode` | On by default. After a reply, keeps listening for a follow-up so you don't have to say the wake word every turn. |
| `followUpWindow` | Seconds to listen for a follow-up after a reply before returning to wake-word mode. |
| `greetOnLaunch` | On by default. Speaks a time-appropriate greeting when the app starts. |
| `userName` | Optional name for a personalized greeting (e.g. "Good morning, Dhruv."). `null` for none. |
| `speechLocale` | Speech-recognition locale. `"en-IN"` (default) understands Indian-accented English best; `"en-US"`, `"en-GB"`, etc. also work. Falls back automatically if unsupported. |
| `allowWebSearch` | On by default. Lets Claude search the web (Anthropic's hosted web-search tool) before answering. Needs a recent model — the default `claude-sonnet-5` supports it. |

Restart the app after hand-editing the config file. `conversationMode`, `greetOnLaunch`, and the
allow-flags also have menu bar toggles.

## Conversation mode

With `conversationMode` on (default), after Jarvis finishes speaking it keeps listening for
`followUpWindow` seconds (default 8) — during which you can give another command **without**
saying "Jarvis" again, so a back-and-forth flows naturally. The mic is muted while Jarvis is
actually speaking, so it never transcribes its own voice. If you don't say anything within the
window, it quietly returns to waiting for the wake word. Toggle it from the menu bar or config.

## Greeting at launch

With `greetOnLaunch` on (default), Jarvis speaks "Good morning/afternoon/evening[, name]. Jarvis
is online and ready." when it starts. Combined with Launch at Login (below), that means it greets
you automatically each time you log in. Set `userName` in the config for a personalized greeting.

## Running without Terminal (the double-clickable app)

Running `.build/release/JarvisAssistant` from Terminal ties the app to that Terminal window —
closing the window quits Jarvis. To run it as a normal background app instead:

```bash
./Scripts/package_app.sh
```

This builds and assembles **`~/Applications/JarvisAssistant.app`** — a menu-bar-only app (no Dock
icon) you can double-click. Because it's ad-hoc signed rather than notarized by Apple, the very
first time you must **right-click it in Finder → Open** to get past Gatekeeper (after that,
double-click works). It keeps running after you close Terminal, and quits from its own menu.

Setting the API key in the app: open its menu bar icon → **Change Anthropic API Key…** and paste
your key there (that stores it in the Keychain under the app's identity). Alternatively drop the
key into `~/JarvisAssistant/api-key.txt` and the app will pick it up.

## Launch at login / background

Once you're running the packaged app, toggle **Launch at Login** from the menu bar icon. This
installs a `launchd` LaunchAgent (`~/Library/LaunchAgents/com.jarvis.assistant.plist`) pointed at
the app, so Jarvis starts automatically and greets you at every login.

**Important:** `launchd` starts it headlessly at login — it can't show the Microphone / Speech
Recognition permission prompts at that point. Launch the app manually once first and grant both
permissions before enabling Launch at Login.

## Doing things inside other apps

Beyond opening apps and running AppleScript, Jarvis can drive app interfaces directly with the
`type_text` and `press_key` tools (typing and key presses via System Events), plus a `wait` tool
to let apps catch up. Its instructions include recipes for common tasks:

- **WhatsApp** — opens `https://wa.me/<number>?text=…` (message pre-filled), waits, then presses
  Return to send. It'll ask for the phone number if it doesn't have one. Say e.g. *"Jarvis,
  message +91 98765 43210 on WhatsApp and say I'm running late."*
- **Email (Apple Mail)** — composes and sends via Mail's AppleScript. Say *"Jarvis, email
  john@example.com with the subject Hello and tell him the report is ready."*
- **Anything else** — it can focus an app and type/click through its UI. For long messages or
  text with emoji/special characters it uses `paste_text` (clipboard + paste), which is more
  reliable than typing key-by-key.
- **Questions / drafting / advice** — it answers from Claude's knowledge.
- **Looking things up** — when the answer needs current or factual info (news, weather, prices,
  scores, recent events), Jarvis searches the web first via Anthropic's hosted web-search tool
  (`allowWebSearch`, on by default) instead of guessing. Say *"Jarvis, what's the weather in
  Mumbai right now?"* or *"Jarvis, who won the match last night?"*

**Switching models:** pick a model from the menu bar icon → **Model** submenu — Opus 4.8/4.7/4.6,
Sonnet 5 (default), Sonnet 4.6, Haiku 4.5, or Fable 5. A checkmark shows the current one, and the
change takes effect on your next command (no restart). More capable models (Opus, Fable) give
better answers but cost more per request; Haiku is fastest and cheapest. You can also set any
model string directly in `config.json` (`"model": "..."`) if a newer one ships before the menu is
updated — verify current IDs at https://docs.anthropic.com/en/docs/about-claude/models. If you
pick a model your account can't access, you'll hear an error on the next command — just switch
back.

**One-time permission for this:** typing into other apps requires macOS **Accessibility**
permission. The first time Jarvis tries it, macOS will prompt — or grant it yourself under
**System Settings → Privacy & Security → Accessibility** by enabling JarvisAssistant. Without it,
`type_text`/`press_key` fail (the tool result says so).

## Understanding your accent

Speech recognition defaults to **Indian English (`en-IN`)** via `speechLocale` in the config, which
handles Indian-accented English far better than US English. For the best offline accuracy, add
Indian English under **System Settings → Keyboard → Dictation → Languages** (and/or enable Siri in
that language) so the on-device model is installed. Change `speechLocale` if you prefer another
variant.

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
