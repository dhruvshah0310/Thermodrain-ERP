#!/bin/bash
# Builds JarvisAssistant and assembles a double-clickable JarvisAssistant.app bundle in
# ~/Applications, so it runs without a Terminal window and survives closing Terminal.
#
# The bundle:
#   * is a menu-bar-only agent (LSUIElement) — no Dock icon,
#   * carries the microphone / speech-recognition usage strings macOS requires to prompt for and
#     remember those permissions,
#   * has a stable bundle identifier so its granted permissions and Keychain access persist across
#     rebuilds,
#   * is ad-hoc code-signed so macOS treats it as one consistent app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="JarvisAssistant"
BUNDLE_ID="com.jarvis.assistant"
DEST="$HOME/Applications/$APP_NAME.app"

echo "Building release binary…"
swift build -c release
BIN=".build/release/$APP_NAME"

echo "Assembling $DEST …"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
mkdir -p "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/$APP_NAME"

cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Jarvis</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSMicrophoneUsageDescription</key>
        <string>Jarvis listens for the wake word and your spoken commands.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
        <string>Jarvis transcribes your spoken commands so it can act on them.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign (the "-" identity). Personal use only; not a Developer ID signature.
echo "Code-signing (ad-hoc)…"
codesign --force --deep --sign - "$DEST"

echo ""
echo "Done. JarvisAssistant.app is in your Applications folder."
echo "First launch: right-click it in Finder → Open (once), to get past Gatekeeper."
echo "It will appear as a waveform icon in your menu bar."
