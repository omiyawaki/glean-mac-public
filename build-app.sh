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
TOOLS_REPO="${APPLE_APP_TOOLS_REPO:-$REPO/../apple-app-tools}"

if [[ ! -d "$TOOLS_REPO" ]]; then
    echo "apple-app-tools repo not found at: $TOOLS_REPO" >&2
    exit 1
fi

echo "Building (configuration: ${CONFIG})..."
swift build -c "$CONFIG"

echo "Wrapping in app bundle at ${APP}..."
if [[ "$LEGACY_APP" != "$APP" && -e "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
fi
RESOURCE_ARGS=()
if [[ -f "$REPO/Resources/Assets.car" ]]; then
    RESOURCE_ARGS+=(--resource "$REPO/Resources/Assets.car")
fi
if [[ -f "$REPO/Resources/AppIcon.icns" ]]; then
    RESOURCE_ARGS+=(--resource "$REPO/Resources/AppIcon.icns")
fi
if [[ -d "$REPO/Resources/AppIcon.icon" ]]; then
    RESOURCE_ARGS+=(--resource "$REPO/Resources/AppIcon.icon")
fi

swift run --package-path "$TOOLS_REPO" -c release apple-app-tools mac package \
    --config "$REPO/AppleAppBlueprint.yaml" \
    --binary "$BIN" \
    --plist "$REPO/Resources/Info.plist" \
    "${RESOURCE_ARGS[@]}"

echo "Done: ${APP}"
