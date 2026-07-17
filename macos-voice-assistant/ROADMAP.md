# Jarvis Autonomous Improvement Roadmap

Worked top-to-bottom by the autonomous loop. Goal: Jarvis performs online tasks like Claude and
does everything on the Mac a human can, accuracy over speed. Items get checked off as implemented
(implemented = written + committed; NOT yet compiled/tested on a Mac — see caveats in each commit).

## In progress / next

- [ ] **web_fetch server tool** — let Claude read a specific URL's contents (Anthropic hosted).
- [ ] **Read screen context** — frontmost app name + window title + selected text, injected so
      Claude always knows what the user is looking at.

## Backlog (rough priority)

- [ ] **web_fetch server tool** — let Claude read a specific URL's contents (Anthropic hosted).
- [ ] **Clipboard read/write tools** — `read_clipboard`, `set_clipboard`.
- [ ] **Read screen context** — frontmost app name + window title + selected text, injected so
      Claude always knows what the user is looking at.
- [ ] **System control tools** — volume, brightness, mute, Do Not Disturb, sleep/lock, wifi
      toggle, media play/pause, screenshot-to-file.
- [ ] **Full file access mode** (config-gated, off by default) — read/write/move/delete files
      anywhere, list directories, open files — so Jarvis can manage the whole disk like a human.
      Keep the destructive-pattern denylist as an accident net.
- [ ] **Dedicated app tools** — Calendar (create/list events), Reminders (add/list), Notes
      (create), Mail (send/search), Messages (send iMessage), Music (play/pause/skip), Finder.
- [ ] **Conversation memory** — retain the last several turns across commands so follow-ups have
      context ("open it", "reply to him").
- [ ] **Persistent memory file** — a notes file Jarvis reads at start and writes learnings to, so
      it remembers facts/preferences across sessions.
- [ ] **Verify-after-action** — after a UI action, screenshot and confirm it worked; retry or
      report honestly if not.
- [ ] **Barge-in** — let the user interrupt Jarvis mid-reply by speaking.
- [ ] **Better errors spoken aloud** — surface API/tool errors as short spoken messages.
- [ ] **Answer length control** — keep spoken answers concise unless asked to elaborate.
- [ ] **Web search result citations** — optionally speak the source when it searched.
- [ ] **Robust JSON/tool-input parsing** — already parsed as dict; audit for edge cases.

## Done

- [x] **Screen vision (computer use)** — `screenshot` tool captures the main display, downscales to
      logical points, returns it as a base64 PNG in the tool result so Claude can see it.
- [x] **Mouse control** — `click`, `double_click`, `right_click`, `move_mouse`, `scroll` via
      CoreGraphics CGEvent (native, top-left-origin point coords matching the screenshot).
- [x] **Screen-aware action loop** — system prompt tells Jarvis to screenshot → look → act →
      screenshot to verify. Gated by `allowScreenControl` (+ menu toggle).
