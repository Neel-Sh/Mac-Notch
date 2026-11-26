#!/usr/bin/env bash
# Records the README demo: the island touring its states in demo mode (fictional data only).
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/DerivedData/Build/Products/Debug/Brim.app"
work="$(mktemp -d)"
mkdir -p "$work/frames" "$work/composed" assets
swiftc -O scripts/record.swift -o "$work/record" 2>/dev/null

pkill -x Brim || true
sleep 0.6
open "$app" --args -demo YES -demoTour YES
sleep 0.8
"$work/record" "$work/frames" 17

pkill -x Brim || true
python3 -I scripts/compose.py "$work/frames" "$work/composed" --frames
ffmpeg -loglevel error -y -framerate 30 -i "$work/composed/timeline/%05d.png" \
  -vf "fps=24,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  assets/demo.gif
ls -lh assets/demo.gif
