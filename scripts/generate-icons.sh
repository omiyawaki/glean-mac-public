#!/bin/bash
# Regenerate Glean app icon assets.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

ICON_DOC="$REPO/Resources/AppIcon.icon"
TOOL_REPO="${APPLE_APP_TOOLS_REPO:-$REPO/../apple-app-tools}"

if [[ ! -d "$TOOL_REPO" ]]; then
    echo "apple-app-tools repo not found at: $TOOL_REPO" >&2
    exit 1
fi

if [[ ! -d "$ICON_DOC" ]]; then
    echo "Missing Icon Composer document: $ICON_DOC" >&2
    exit 1
fi

swift run --package-path "$TOOL_REPO" -c release icon-composer-build build \
    --icon "$ICON_DOC" \
    --name AppIcon \
    --out "$REPO/Resources" \
    --work "$REPO/.build/icon-composer-build" \
    --review "$REPO/.build/icon-review" \
    --review-sheet "$REPO/.build/icon-review/glean-icon-review.png" \
    --platform macOS \
    --minimum-deployment-target 26.0 \
    --verify-plist "$REPO/Resources/Info.plist"
