#!/usr/bin/env bash
# Builds Brim in Release and puts it in /Applications (or the folder you pass), then opens it.
#   scripts/install.sh [folder] [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."
destination="/Applications"
open_after=yes
for argument in "$@"; do
  if [[ "$argument" == --no-open ]]; then open_after=no; else destination="$argument"; fi
done

echo "Building Brim…"
xcodebuild -project Brim.xcodeproj -scheme Brim -configuration Release \
  -derivedDataPath build/DerivedData -quiet build

osascript -e 'tell application id "com.neelsharma.brim" to quit' >/dev/null 2>&1 || true
mkdir -p "$destination"
rm -rf "$destination/Brim.app"
ditto build/DerivedData/Build/Products/Release/Brim.app "$destination/Brim.app"
echo "Installed $destination/Brim.app"
[[ "$open_after" == yes ]] && open "$destination/Brim.app"
