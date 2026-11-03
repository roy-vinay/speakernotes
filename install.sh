#!/bin/bash
# Installs or updates SpeakerNotes in /Applications. Run it again any time to get the newest version:
#   curl -fsSL https://raw.githubusercontent.com/roy-vinay/speakernotes/main/install.sh | bash
set -euo pipefail

URL="https://github.com/roy-vinay/speakernotes/releases/latest/download/SpeakerNotes-macOS.zip"
DEST="/Applications/SpeakerNotes.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(uname)" = "Darwin" ] || { echo "SpeakerNotes is a Mac app."; exit 1; }

echo "Downloading the latest SpeakerNotes..."
curl -fL --progress-bar "$URL" -o "$TMP/SpeakerNotes-macOS.zip"
ditto -x -k "$TMP/SpeakerNotes-macOS.zip" "$TMP"

# Quit the running copy so it can be replaced. Your notes and settings are kept.
osascript -e 'quit app "SpeakerNotes"' >/dev/null 2>&1 || true
sleep 1
pkill -x SpeakerNotes >/dev/null 2>&1 || true

rm -rf "$DEST"
mv "$TMP/SpeakerNotes.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"

VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")"
echo "SpeakerNotes $VERSION is installed. Look for its icon in the menu bar."
