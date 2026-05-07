#!/bin/bash
# Build Glean and wrap the SPM binary in a proper .app bundle.
# Output: ~/Applications/Glean.app - double-click or `open ~/Applications/Glean.app` to run.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

CONFIG="${CONFIG:-debug}"
APP="$HOME/Applications/Glean.app"
BIN="$REPO/.build/arm64-apple-macosx/$CONFIG/GleanMac"
LEGACY_APP="$HOME/Applications/glean.app"

echo "Building (configuration: ${CONFIG})..."
swift build -c "$CONFIG"

echo "Wrapping in app bundle at ${APP}..."
rm -rf "$APP"
if [[ "$LEGACY_APP" != "$APP" && -e "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GleanMac"
cp "$REPO/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$REPO/Resources/Assets.car" ]]; then
    cp "$REPO/Resources/Assets.car" "$APP/Contents/Resources/Assets.car"
fi
if [[ -f "$REPO/Resources/AppIcon.icns" ]]; then
    cp "$REPO/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -d "$REPO/Resources/AppIcon.icon" ]]; then
    cp -R "$REPO/Resources/AppIcon.icon" "$APP/Contents/Resources/AppIcon.icon"
fi
# Ad-hoc sign so launch services / TCC treat the wrapper as a real local app.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi
touch "$APP"

echo "Done: ${APP}"
