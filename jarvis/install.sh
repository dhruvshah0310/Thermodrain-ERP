#!/usr/bin/env bash
# Jarvis installer for macOS.
#
#   ./install.sh
#
# Creates a virtualenv, installs dependencies, downloads the wake-word model,
# writes ~/.jarvis/config.json, and (optionally) installs a LaunchAgent so
# Jarvis starts at login.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv"
PY="${PYTHON:-python3}"

echo "▶ Jarvis installer"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "⚠  Jarvis targets macOS. Continuing, but Mac-control and voice features may not work."
fi

# PortAudio is needed by sounddevice.
if command -v brew >/dev/null 2>&1; then
  brew list portaudio >/dev/null 2>&1 || { echo "▶ Installing portaudio…"; brew install portaudio; }
else
  echo "⚠  Homebrew not found — install it from https://brew.sh so PortAudio (mic access) is available."
fi

echo "▶ Creating virtualenv at $VENV"
"$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
python -m pip install --upgrade pip wheel >/dev/null

echo "▶ Installing Python dependencies (this can take a few minutes)…"
pip install -r "$HERE/requirements.txt"

echo "▶ Downloading wake-word model (hey_jarvis)…"
python - <<'PY' || echo "  (wake word download skipped — push-to-talk will still work)"
import openwakeword.utils
openwakeword.utils.download_models(["hey_jarvis"])
print("  ✓ wake-word model ready")
PY

echo "▶ Writing default config…"
python -m jarvis --config >/dev/null

CFG="$HOME/.jarvis/config.json"
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo
  echo "  Set your Anthropic API key so Jarvis can answer internet questions:"
  echo "     export ANTHROPIC_API_KEY=sk-ant-...   (add to ~/.zshrc)"
  echo "  …or add \"api_key\" to $CFG"
fi

read -r -p "▶ Start Jarvis automatically at login? [y/N] " REPLY || true
if [[ "${REPLY:-N}" =~ ^[Yy]$ ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.jarvis.assistant.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  sed -e "s#__PYTHON__#$VENV/bin/python#g" -e "s#__DIR__#$HERE#g" \
      "$HERE/packaging/com.jarvis.assistant.plist" > "$PLIST"
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "  ✓ LaunchAgent installed. Jarvis will start at login."
fi

echo
echo "✅ Done. Start Jarvis now with:"
echo "     source $VENV/bin/activate && python -m jarvis"
echo
echo "   First run will ask for Microphone and Accessibility permissions —"
echo "   grant both in System Settings for wake word + Mac control to work."
