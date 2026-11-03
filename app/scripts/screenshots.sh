#!/bin/bash
# Takes screenshots of the built app (run on a Mac after build-app.sh; CI does this), and checks that
# the notes window stays out of a full-screen capture when "Hide from Screen Share" is on.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/SpeakerNotes.app"
OUT="$PWD/../docs/img"
NOTES="$PWD/../examples/sample-talk.md"
DOMAIN=io.github.roy-vinay.speakernotes
mkdir -p "$OUT"
rm -f "$OUT"/app-*.png "$OUT"/capture-*.png

launch() { # extra app arguments...
  defaults delete "$DOMAIN" >/dev/null 2>&1 || true
  open -n -a "$APP" --args -hiddenFromShare NO "$@"
  sleep 6
}
quit() { pkill -x SpeakerNotes || true; sleep 2; }

window() { # name
  local id
  id="$(swift scripts/window_id.swift SpeakerNotes)"
  screencapture -x -o -l "$id" "$OUT/$1.png"
  echo "Saved $OUT/$1.png"
}

launch -filePath "$NOTES" -slideIndex 1
window app-present
quit

launch -filePath "" -notes ""
window app-empty
quit

launch -filePath "$NOTES" -slideIndex 1 -startEditing YES
window app-edit
quit

# Popovers are their own windows, so capture the whole screen for these.
launch -filePath "$NOTES" -slideIndex 1 -openPopover text
screencapture -x "$OUT/app-text-settings.png"
quit
launch -filePath "$NOTES" -slideIndex 1 -openPopover emphasis
screencapture -x "$OUT/app-emphasize.png"
quit

# The real test: a full-screen capture with hiding on, then off.
defaults delete "$DOMAIN" >/dev/null 2>&1 || true
open -n -a "$APP" --args -filePath "$NOTES" -slideIndex 1 -hiddenFromShare YES
sleep 6
screencapture -x "$OUT/capture-hidden.png"
quit
launch -filePath "$NOTES" -slideIndex 1
screencapture -x "$OUT/capture-visible.png"
quit
ls -la "$OUT"
