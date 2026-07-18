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
    <key>NSAppleEventsUsageDescription</key>
        <string>Jarvis controls apps (AppleScript / System Events) to carry out your commands.</string>
    <key>NSCameraUsageDescription</key>
        <string>Jarvis uses the camera for hand-gesture motion control when you enable it.</string>
</dict>
</plist>
PLIST

# Sign with the camera / microphone / Apple-Events entitlements plus the Info.plist usage strings —
# together these let macOS prompt for and remember Camera, Microphone, and automation access.
#
# IMPORTANT: ad-hoc ("-") signatures change on every rebuild, so macOS treats each build as a new app
# and your granted permissions (especially Accessibility, which never re-prompts) silently stop
# applying. To make permissions PERSIST across rebuilds, create a one-time self-signed code-signing
# certificate named "Jarvis Local Signing" (Keychain Access > Certificate Assistant > Create a
# Certificate… > Code Signing). If it exists we use it; otherwise we fall back to ad-hoc.
SIGN_IDENTITY="Jarvis Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "Code-signing with stable identity '$SIGN_IDENTITY' (permissions persist across rebuilds)…"
    SIGN_ARG="$SIGN_IDENTITY"
else
    echo "Code-signing (ad-hoc — permissions must be re-granted after each rebuild; see notes in this script)…"
    SIGN_ARG="-"
fi
codesign --force --deep --entitlements "$(dirname "$0")/Jarvis.entitlements" --sign "$SIGN_ARG" "$DEST"

echo ""
echo "Done. JarvisAssistant.app is in your Applications folder."
echo "First launch: right-click it in Finder → Open (once), to get past Gatekeeper."
echo "It will appear as a waveform icon in your menu bar."
