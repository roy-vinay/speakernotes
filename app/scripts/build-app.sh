#!/bin/bash
# Builds SpeakerNotes.app (Apple silicon and Intel) and a zip for download.
# The app is ad-hoc signed, not notarized; see the README for how to open it.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product SpeakerNotes
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=build/SpeakerNotes.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SpeakerNotes" "$APP/Contents/MacOS/SpeakerNotes"
cp Info.plist "$APP/Contents/Info.plist"

# App icon, in every size macOS asks for.
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Icon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/SpeakerNotes"

(cd build && ditto -c -k --keepParent SpeakerNotes.app SpeakerNotes-macOS.zip)
echo "Built $(pwd)/build/SpeakerNotes.app and build/SpeakerNotes-macOS.zip"
