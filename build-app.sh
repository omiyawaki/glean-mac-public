#!/bin/bash
# Build Glean and wrap the SPM binary in a proper .app bundle.
# Output: ~/Applications/Glean.app - double-click or `open ~/Applications/Glean.app` to run.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

CONFIG="${CONFIG:-debug}"
APP="$HOME/Applications/Glean.app"
LEGACY_APP="$HOME/Applications/glean.app"

# Package.swift pulls apple-app-tools from its remote repository for the
# library targets. The packaging step below runs the `apple-app-tools` CLI
# from a local checkout; point APPLE_APP_TOOLS_REPO at one
# (https://github.com/omiyawaki/apple-app-tools-public).
TOOLS_REPO="${APPLE_APP_TOOLS_REPO:-$HOME/tools/apple-app-tools}"
if [[ ! -d "$TOOLS_REPO" ]]; then
    echo "apple-app-tools checkout not found at: $TOOLS_REPO" >&2
    echo "Set APPLE_APP_TOOLS_REPO to a clone of apple-app-tools-public." >&2
    exit 1
fi

echo "Building (configuration: ${CONFIG})..."
swift build -c "$CONFIG"
# SwiftPM's build layout is .build/<config> or .build/out/Products/<Config>.
# Ask the tool instead of hard-coding the old triple directory, which can
# still hold a stale binary after the layout changes.
BIN="$(swift build -c "$CONFIG" --show-bin-path)/GleanMac"
if [[ ! -x "$BIN" ]]; then
    echo "built binary not found at $BIN" >&2
    exit 1
fi

echo "Wrapping in app bundle at ${APP}..."
# Drop the lowercase legacy bundle if it's a distinct artifact from any
# bundle we're managing. APFS is case-insensitive by default, so `glean.app`
# and `Glean.app` share an inode. Compare inodes against every
# managed bundle path before removing.
if [[ -e "$LEGACY_APP" ]]; then
    LEGACY_INODE="$(stat -f %i "$LEGACY_APP" 2>/dev/null || echo legacy)"
    SAFE_TO_DELETE=1
    for managed in "$HOME/Applications/Glean.app"; do
        if [[ -e "$managed" ]]; then
            MANAGED_INODE="$(stat -f %i "$managed" 2>/dev/null || echo managed)"
            if [[ "$LEGACY_INODE" == "$MANAGED_INODE" ]]; then
                SAFE_TO_DELETE=0
                break
            fi
        fi
    done
    if [[ "$SAFE_TO_DELETE" == "1" ]]; then
        rm -rf "$LEGACY_APP"
    fi
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
if [[ -f "$REPO/Sources/GleanMac/Resources/darkreader.js" ]]; then
    RESOURCE_ARGS+=(--resource "$REPO/Sources/GleanMac/Resources/darkreader.js")
fi

PLIST_ARG="$REPO/Resources/Info.plist"

swift run --package-path "$TOOLS_REPO" -c release apple-app-tools mac package \
    --config "$REPO/AppleAppBlueprint.yaml" \
    --binary "$BIN" \
    --plist "$PLIST_ARG" \
    "${RESOURCE_ARGS[@]}"

echo "Done: ${APP}"

