#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="${BUILD_APP_PATH:-$PWD/dist/Menu Bar Panel.app}"
VERSION="${VERSION:-0.1.1}"
BUILD="${BUILD:-2}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application:/ {print $2; exit}')}"
if [[ -z "$SIGN_IDENTITY" ]]; then
    print -u2 'Set CODE_SIGN_IDENTITY to a stable signing identity. For an explicit disposable ad-hoc build use CODE_SIGN_IDENTITY=-; its TCC grants will not survive changes.'
    exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$PWD/.build/module-cache" Sources/*.swift -o "$APP/Contents/MacOS/MenuBarPanel" -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework ServiceManagement
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MenuBarPanel</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>net.thealex.menu-bar-panel</string>
<key>CFBundleName</key><string>Menu Bar Panel</string>
<key>CFBundleDisplayName</key><string>Menu Bar Panel</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp LICENSE THIRD_PARTY.md "$APP/Contents/Resources/"
xcrun actool --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$PWD/.build/icon.plist" "$PWD/Resources/AppIcon.icon" >/dev/null
TIMESTAMP=--timestamp=none
[[ "${RELEASE:-}" == 1 ]] && TIMESTAMP=--timestamp
codesign --force --options runtime --sign "$SIGN_IDENTITY" --identifier net.thealex.menu-bar-panel $TIMESTAMP "$APP"
codesign --verify --strict "$APP"
print "$APP"
