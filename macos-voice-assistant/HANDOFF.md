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

## Exact next 3 steps
1. **Full-disk file access mode** — add config `allowFullFileAccess` (default false) + tools
   `read_any_file`, `write_any_file`, `list_directory`, `move_path`, `delete_path`, `open_path`
   (tilde-expanded absolute paths; reuse shell denylist idea for deletes). Wire into
   `ToolDefinition.swift` + `ToolExecutor.swift`; they auto-appear in MCP.
2. **Conversation memory** — keep last ~6 turns in `JarvisController` and pass prior turns to
   `ClaudeClient.converse` so follow-ups ("reply to him", "open it") have context. Clear on a long
   idle gap.
3. **Verify-after-action** — prompt guidance already asks for screenshot-to-verify; add a light
   post-action screenshot on UI tool sequences and have Claude confirm/retry.

## Watch-outs for the new chat
- Cannot compile here — keep changes isolated, flag untested.
- AppleScript app tools need the target apps installed/signed in; `send_imessage` needs Messages
  signed in. Screen/mouse need Accessibility + Screen Recording (grant to Claude Desktop for MCP).
- Commit + push each change to the branch; do not open a PR unless asked.
