# Jarvis Autonomous Improvement Roadmap

Worked top-to-bottom by the autonomous loop. Goal: Jarvis performs online tasks like Claude and
does everything on the Mac a human can, accuracy over speed. Items get checked off as implemented
(implemented = written + committed; NOT yet compiled/tested on a Mac — see caveats in each commit).

## In progress / next

- [ ] **Persistent memory file** — a notes file Jarvis reads at start and writes learnings to, so
      it remembers facts/preferences across sessions (builds on the in-session conversation memory).
- [ ] **Barge-in** — let the user interrupt Jarvis mid-reply by speaking.
- [ ] **Better errors spoken aloud** — surface API/tool errors as short spoken messages.

## Backlog (rough priority)

- [ ] **Dedicated app tools (more)** — Calendar (list events), Reminders (list), Mail (send/search),
      Finder operations beyond open_path.
- [ ] **Answer length control** — keep spoken answers concise unless asked to elaborate.
- [ ] **Better errors spoken aloud** — surface API/tool errors as short spoken messages.
- [ ] **Answer length control** — keep spoken answers concise unless asked to elaborate.
- [ ] **Web search result citations** — optionally speak the source when it searched.
- [ ] **Robust JSON/tool-input parsing** — already parsed as dict; audit for edge cases.

## Done

- [x] **Full file access mode** (config-gated, off by default) — `read_any_file`, `write_any_file`,
      `list_directory`, `move_path`, `delete_path`, `open_path` work anywhere on disk (tilde-expanded
      absolute paths). Deletes are refused for a denylist of critical system/home paths as an
      accident net. Gated by `allowFullFileAccess` (+ menu toggle); auto-appears in the MCP server.
- [x] **Conversation memory** — the controller keeps the last ~6 plain-text user/assistant turns and
      passes them to `ClaudeClient.converse`, so follow-ups ("reply to him", "open it") have context.
      Cleared after `conversationMemoryTimeout` seconds of idle so stale context doesn't leak into an
      unrelated command.
- [x] **Verify-after-action** — blind keystroke tools (`type_text`, `press_key`, `paste_text`) append
      a nudge to screenshot and confirm before claiming success (gated by `verifyActions` +
      `allowScreenControl`), reinforced in the system prompt.
- [x] **Screen vision (computer use)** — `screenshot` tool captures the main display, downscales to
      logical points, returns it as a base64 PNG in the tool result so Claude can see it.
- [x] **Mouse control** — `click`, `double_click`, `right_click`, `move_mouse`, `scroll` via
      CoreGraphics CGEvent (native, top-left-origin point coords matching the screenshot).
- [x] **Screen-aware action loop** — system prompt tells Jarvis to screenshot → look → act →
      screenshot to verify. Gated by `allowScreenControl` (+ menu toggle).
- [x] **web_fetch server tool** — added alongside web_search (both `_20260209`) so Claude can read
      a specific URL's full content, gated by `allowWebSearch`.
- [x] **Screen context tool** — `get_screen_context` reports the frontmost app + front window
      title so Jarvis knows what "this"/"the current window" refers to.
- [x] **Clipboard tools** — `read_clipboard` and `set_clipboard`.
- [x] **MCP connector** — the same binary runs as an MCP server (`--mcp`, stdio JSON-RPC) exposing
      all local Mac-control tools, so Claude Desktop can operate the Mac. Logger now writes to
      stderr so it never corrupts the protocol stream on stdout.
- [x] **System control tools** — `set_volume`, `get_volume`, `set_mute`, `adjust_brightness`,
      `lock_screen`, `system_sleep`.
- [x] **Dedicated app tools** — `control_music`, `add_reminder`, `create_note`, `send_imessage`,
      `create_calendar_event` (dates built via component-setting AppleScript to avoid locale
      parsing issues). All flow into the MCP connector automatically.
