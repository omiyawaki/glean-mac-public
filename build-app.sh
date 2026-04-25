#!/bin/bash
# Build glean-mac and wrap the SPM binary in a proper .app bundle.
# Output: ./glean.app — double-click or `open glean.app` to run.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

CONFIG="${CONFIG:-debug}"
APP="$REPO/glean.app"
BIN="$REPO/.build/arm64-apple-macosx/$CONFIG/GleanMac"

echo "Building (configuration: $CONFIG)…"
swift build -c "$CONFIG"

echo "Wrapping in app bundle at $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GleanMac"
cp "$REPO/Resources/Info.plist" "$APP/Contents/Info.plist"
# ad-hoc sign so launchd / TCC don't reject the unsigned binary
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Done: $APP"
