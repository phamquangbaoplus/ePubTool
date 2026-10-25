#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/ePubTool.app /path/to/output.dmg" >&2
    exit 1
fi
app="$1"
output="$2"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$script_dir")"
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
ln -s /Applications "$staging/Applications"
cp "$repo_dir/packaging/READ ME FIRST.txt" "$staging/READ ME FIRST.txt"
hdiutil create -volname "ePubTool — Install" -srcfolder "$staging" \
    -format UDZO -ov "$output"
hdiutil verify "$output"
