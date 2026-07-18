# Jarvis — Transfer Packet

**Repo:** dhruvshah0310/Thermodrain-ERP · **Branch:** `claude/macos-voice-assistant-v5wmb6`
**Code dir:** `macos-voice-assistant/` (Swift Package). Build: `swift build -c release`. Run:
`.build/release/JarvisAssistant` (voice app) or `... --mcp` (MCP server). Package `.app`:
`Scripts/package_app.sh`. Config: `~/Library/Application Support/JarvisAssistant/config.json`.

## Current objective
A macOS voice assistant ("Jarvis") + an MCP server (same binary, `--mcp`) so Claude Desktop can
operate the Mac. Goal: do everything a human can on the Mac + online tasks like Claude, accuracy
over speed. **All code is written WITHOUT a Mac toolchain — never compiled.** First real task on a
Mac is a build-check/cleanup pass.

## Files (all under macos-voice-assistant/Sources/JarvisAssistant/)
- `Config.swift` — settings + resilient JSON decode (new keys don't break old files).
- `SpeechEngine.swift` — wake-word listen; generation-guarded task rotation; accumulates long
  commands; en-IN locale; mute + follow-up.
- `SpeechOutput.swift` — TTS. `ClaudeClient.swift` — Anthropic loop (tool_use + pause_turn, web
  server tools, image tool-results). `KeychainStore.swift`, `Logger.swift` (writes to **stderr**).
- `ToolDefinition.swift` — all tool schemas + `serverTools` (web_search/fetch).
- `ToolExecutor.swift` — actor implementing every tool (returns `ToolResult{text,image}`).
- `JarvisController.swift` — orchestrator + system prompt. `StatusBarController.swift` — menu +
  model picker. `MCPServer.swift` — stdio JSON-RPC. `main.swift` — `--mcp` switch.
- Docs: `README.md`, `ROADMAP.md`, `JARVIS_APP_REMINDERS.md`.

## Decisions & why
- **One binary, two modes** (`--mcp`) — MCP reuses `ToolExecutor`, so every tool works in both
  voice + Claude Desktop with zero duplication.
- **Logger → stderr** — stdout is the MCP JSON-RPC channel; logs there would corrupt it.
- **Screenshot downscaled to logical points** — so Claude's pixel coords map 1:1 to CGEvent
  mouse clicks (fixes Retina 2x mismatch).
- **Calendar/Reminder dates built by setting AppleScript components** (day→1 first) — avoids
  locale-dependent `date "…"` parsing bugs.
- **Config flags gate tools** (`allowShellCommands` off; `allowScreenControl`, `allowWebSearch`,
  etc. on) — same gating applies to the MCP server. Shell denylist kept as an accident net.
- **Model picker** in menu; model read live per command.

## Recently completed (this pass — written, NOT compiled on a Mac)
1. **Full-disk file access mode** — DONE. Config `allowFullFileAccess` (default false) + tools
   `read_any_file`, `write_any_file`, `list_directory`, `move_path`, `delete_path`, `open_path`
   (tilde-expanded absolute paths). `delete_path` refuses a denylist of critical system/home paths.
   Wired into `ToolDefinition.swift` + `ToolExecutor.swift` (auto-appears in MCP) + a menu toggle in
   `StatusBarController.swift`.
2. **Conversation memory** — DONE. `JarvisController` keeps the last ~6 plain-text turns
   (`conversationHistory`), passes them via a new `history:` param on `ClaudeClient.converse`, and
   clears them after `conversationMemoryTimeout` (default 180s) idle.
3. **Verify-after-action** — DONE. `verifyActions` config (default true): `type_text`/`press_key`/
   `paste_text` results append a screenshot-and-confirm nudge when screen control is on; system
   prompt reinforced.

Note: `ToolExecutor` is now built per-command from live config in `JarvisController.handle` (not
once at init) so menu toggles take effect immediately instead of only after relaunch.

## Exact next 3 steps
1. **Build-check on a real Mac** — first task on a Mac: `swift build -c release`, fix any compile
   errors (none of the above is compiled yet), then smoke-test full file access, memory follow-ups,
   and the verify nudge.
2. **Persistent memory file** — a notes file Jarvis reads at launch and appends learnings/preferences
   to, so facts survive across sessions (the conversation memory above is in-RAM only).
3. **Barge-in** — let the user interrupt Jarvis mid-reply by speaking (stop TTS + capture).

## Watch-outs for the new chat
- Cannot compile here — keep changes isolated, flag untested.
- AppleScript app tools need the target apps installed/signed in; `send_imessage` needs Messages
  signed in. Screen/mouse need Accessibility + Screen Recording (grant to Claude Desktop for MCP).
- Commit + push each change to the branch; do not open a PR unless asked.
