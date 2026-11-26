#!/usr/bin/env bash
# Regenerates every image and recording in the README from demo mode: made-up data on a staged
# desktop, so nothing from your Mac is in the picture. Build first (see CONTRIBUTING.md).
#
#   scripts/media.sh           everything
#   scripts/media.sh shots     the screenshots only
#   scripts/media.sh videos    the two recordings only
#
# Needs Screen Recording allowed for your terminal, plus python3 with Pillow and ffmpeg.
# Keep the pointer away from the notch and the screen edges while it runs: hovering opens the island.
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-all}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/shots" assets/screenshots
swiftc -O scripts/stage.swift -o "$work/stage" 2>/dev/null

# The island as it ships, whatever your own settings are.
defaults=(-pref.edge top -pref.compact NO -pref.material black -pref.hiddenTabs "()")

shot() { # name, view, Brim arguments...
  local name="$1" view="$2"; shift 2
  "$work/stage" shot "$work/shots/$name.png" --view "$view" -- "${defaults[@]}" "$@" >/dev/null
  echo "  $name"
}

record() { # name, view, seconds, Brim arguments...
  local name="$1" view="$2" seconds="$3"; shift 3
  "$work/stage" record "$work/$name.mov" --view "$view" --seconds "$seconds" -- "${defaults[@]}" "$@" >/dev/null
  # An MP4 at full quality, and an animated WebP that plays inline in the README.
  ffmpeg -loglevel error -y -i "$work/$name.mov" -an -vf "fps=60,scale=1920:-2:flags=lanczos" \
    -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart "assets/$name.mp4"
  ffmpeg -loglevel error -y -i "$work/$name.mov" -an -vf "fps=25,scale=1100:-2:flags=lanczos" \
    -c:v libwebp_anim -lossless 0 -q:v 78 -compression_level 6 -loop 0 "assets/$name.webp"
  echo "  $name"
}

if [[ "$what" == all || "$what" == shots ]]; then
  echo "Screenshots"
  page="top:1120x500"
  shot wings          top:820x230
  shot approval       top:1120x400 -demoPeek YES
  shot agents         "$page" -openTab agents
  shot calendar       "$page" -openTab calendar
  shot weather        "$page" -openTab weather
  shot tasks          "$page" -openTab tasks
  shot music          "$page" -openTab media
  shot shelf          "$page" -openTab shelf
  shot shelf-recents  "$page" -openTab shelf -demoRecents YES

  look="1000x600"
  shot look-glass     "top:$look"   -openTab weather -pref.material glass
  shot look-compact   "top:$look"   -openTab calendar -pref.compact YES
  shot look-left      "left:$look"  -openTab agents -pref.edge left
  shot look-right     "right:$look" -openTab media -pref.edge right -pref.material glass

  for tab in general appearance pages agents; do
    shot "settings-$tab" window:44 -openSettings YES -settingsTab "$tab"
  done

  python3 -I scripts/finish.py "$work/shots" assets/screenshots
fi

if [[ "$what" == all || "$what" == videos ]]; then
  echo "Recordings"
  record demo      top:1200x675 19 -demoTour YES
  record customize top:1512x756 20 -demoStyleTour YES
fi

du -sh assets
