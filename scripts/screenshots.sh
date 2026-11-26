#!/usr/bin/env bash
# Captures README screenshots from demo mode: fictional data only, nothing from your Mac.
# Usage: scripts/screenshots.sh  (after building to build/DerivedData)
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/DerivedData/Build/Products/Debug/Brim.app"
out="assets/screenshots"
raw="$(mktemp -d)"
mkdir -p "$out"
swiftc -O scripts/window-id.swift -o "$raw/window-id"

shoot() { # name, launch args...
  local name="$1"; shift
  pkill -x Brim || true
  sleep 0.6
  open "$app" --args -demo YES "$@"
  sleep 3
  screencapture -x -o -l "$("$raw/window-id")" "$raw/$name.png"
}

shoot wings
shoot agents -openTab agents
shoot approval -demoPeek YES
shoot calendar -openTab calendar
shoot weather -openTab weather
shoot tasks -openTab tasks
shoot music -openTab media
shoot shelf -openTab shelf
pkill -x Brim || true

python3 -I scripts/compose.py "$raw" "$out"
echo "Wrote $(ls "$out" | wc -l | tr -d ' ') screenshots to $out"
