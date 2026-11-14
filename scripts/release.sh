#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export VERSION="${VERSION:-0.1.1}"
export RELEASE=1
PROFILE="${NOTARY_PROFILE:-notary}"
APP="$PWD/dist/Menu Bar Panel.app"
ZIP="$PWD/dist/MenuBarPanel-$VERSION-arm64.zip"
scripts/build.sh
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
else
    xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
fi
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
shasum -a 256 "$ZIP" | sed "s#$PWD/dist/##" > dist/SHA256SUMS
print "$ZIP"
