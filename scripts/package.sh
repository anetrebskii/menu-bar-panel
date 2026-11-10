#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/dist/Menu Bar Panel.app"
[[ -x "$APP/Contents/MacOS/MenuBarPanel" ]]
codesign --verify --strict "$APP"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/menu-bar-panel-package.XXXXXX")
trap 'rm -r "$STAGING"' EXIT
ROOT="$STAGING/MenuBarPanel"
mkdir -p "$ROOT/Source"
ditto "$APP" "$ROOT/Menu Bar Panel.app"
for item in Sources Resources scripts doc evidence README.md LICENSE THIRD_PARTY.md; do
    ditto "$item" "$ROOT/Source/$item"
done
ditto -c -k --sequesterRsrc --keepParent "$ROOT" "$PWD/dist/MenuBarPanel-0.1.1-arm64.zip"
shasum -a 256 'dist/Menu Bar Panel.app/Contents/MacOS/MenuBarPanel' dist/MenuBarPanel-0.1.1-arm64.zip > dist/SHA256SUMS
print "$PWD/dist/MenuBarPanel-0.1.1-arm64.zip"
