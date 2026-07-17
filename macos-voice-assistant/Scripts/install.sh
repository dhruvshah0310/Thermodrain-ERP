#!/bin/bash
# Builds a release binary and copies it to a stable location (~/Applications/JarvisAssistant/)
# so the "Launch at Login" menu item can point at a path that survives `swift build` re-runs.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

DEST_DIR="$HOME/Applications/JarvisAssistant"
mkdir -p "$DEST_DIR"
cp .build/release/JarvisAssistant "$DEST_DIR/JarvisAssistant"

echo "Installed to $DEST_DIR/JarvisAssistant"
echo "Run it once from Terminal to grant Microphone + Speech Recognition access:"
echo "  \"$DEST_DIR/JarvisAssistant\""
