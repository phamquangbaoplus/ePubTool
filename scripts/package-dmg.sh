#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/ePubTool.app /path/to/output.dmg" >&2
    exit 1
fi
app="$1"
output="$2"
script_dir="$(cd "$(dirname "$0")" && pwd)"
command -v create-dmg >/dev/null || { echo "Install create-dmg with: brew install create-dmg" >&2; exit 1; }
test -f "$app/Contents/Info.plist"
test -f "$app/Contents/Resources/AppIcon.icns"
# Never overwrite an existing image during a local packaging run.
if [[ -e "$output" ]]; then
    echo "Output already exists: $output" >&2
    exit 1
fi
staging="$(mktemp -d "${TMPDIR:-/tmp}/epubtool-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$(dirname "$output")"
ditto "$app" "$staging/ePubTool.app"
# Keep artwork outside the source folder; create-dmg stores it hidden in the DMG.
swift "$script_dir/dmg-background.swift" "$staging/background.png"
mkdir "$staging/contents"
mv "$staging/ePubTool.app" "$staging/contents/"
create-dmg \
    --volname "ePubTool" \
    --volicon "$app/Contents/Resources/AppIcon.icns" \
    --background "$staging/background.png" \
    --window-pos 200 120 \
    --window-size 660 440 \
    --icon-size 100 \
    --text-size 14 \
    --icon "ePubTool.app" 170 210 \
    --hide-extension "ePubTool.app" \
    --app-drop-link 490 210 \
    "$output" "$staging/contents"
hdiutil verify "$output"
