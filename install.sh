#!/bin/bash
# SpeakerNotes moved to applied-ai-agents/tools/speakernotes. This runs the installer from its new home,
# so the old install command keeps working.
set -euo pipefail
curl -fsSL https://raw.githubusercontent.com/roy-vinay/applied-ai-agents/main/tools/speakernotes/install.sh | bash
