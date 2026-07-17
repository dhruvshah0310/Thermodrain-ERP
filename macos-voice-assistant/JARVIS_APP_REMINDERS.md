# Jarvis App — Reminders & To-Do Before Building the Real App

A running list of things to fix / add / verify before packaging Jarvis as the final
double-clickable Mac app. The user adds items over time (sent as "Jarvis app reminder - do xyz").
Nothing here is built yet unless checked off.

## User-requested reminders

_(none yet — will be appended as they come in)_

## Known open items from testing (pre-seeded)

- [ ] Confirm the Accessibility permission flow works cleanly from the packaged `.app` (vs.
      Terminal, where the permission attaches to Terminal itself). WhatsApp/email typing depends
      on it.
- [ ] Verify on-device speech: make sure the en-IN model is fully installed (Dictation/Siri
      languages) so recognition doesn't fall back to server-based.
- [ ] Decide final model: `claude-sonnet-5` (default, cheaper) vs `claude-opus-4-8` (most
      capable). Consider a menu toggle.
- [ ] Re-test WhatsApp-by-name end to end with the new `paste_text` tool and confirm messages
      actually send (not just "dispatched").
- [ ] Confirm the API key is picked up by the `.app` from Keychain (created under the app's own
      identity via the in-app dialog), not just the Terminal env var.

## Notes for whoever builds it

- Build/run: `swift build -c release` then `.build/release/JarvisAssistant`; package with
  `Scripts/package_app.sh`.
- Config lives at `~/Library/Application Support/JarvisAssistant/config.json`.
- Always quit the running app (Ctrl+C) before rebuilding.
