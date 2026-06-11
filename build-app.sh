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

# Package.swift declares the apple-app-tools dependency as `.package(path:
# "../apple-app-tools")`, which is relative to REPO. The canonical
# checkout lives at ~/tools/apple-app-tools, so that path resolves when
# REPO is ~/tools/glean-mac, but auto-deploy invokes us from a worktree
# under ~/.apple-app-tools/deploy-checkouts/glean-mac/ where the sibling
# directory doesn't exist. If the sibling is missing, drop a temporary
# symlink to the canonical location and clean it up on exit.
SIBLING="$REPO/../apple-app-tools"
SIBLING_CANONICAL="$HOME/tools/apple-app-tools"
SIBLING_SYMLINK=""
if [[ ! -e "$SIBLING" && -d "$SIBLING_CANONICAL" ]]; then
    ln -s "$SIBLING_CANONICAL" "$SIBLING"
    SIBLING_SYMLINK="$SIBLING"
    trap 'rm -f "$SIBLING_SYMLINK"' EXIT
fi
TOOLS_REPO="${APPLE_APP_TOOLS_REPO:-$SIBLING_CANONICAL}"
if [[ ! -d "$TOOLS_REPO" ]]; then
    echo "apple-app-tools repo not found at: $TOOLS_REPO" >&2
    exit 1
fi

echo "Building (configuration: ${CONFIG})..."
swift build -c "$CONFIG"

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

# Opt-in: when invoked with --verify (or BUILD_APP_VERIFY=1), chain into
# apple-app-tools auto-deploy verify. This runs the smoke check, publishes
# the verified/glean-mac/<sha> tag, and notifies peer machines so they
# auto-deploy this commit. Off by default so the smoke launch does not
# disrupt iterative development builds.
VERIFY=0
for arg in "$@"; do
    if [[ "$arg" == "--verify" ]]; then
        VERIFY=1
    fi
done
if [[ "${BUILD_APP_VERIFY:-0}" == "1" ]]; then
    VERIFY=1
fi
if [[ "$VERIFY" == "1" ]]; then
    "$TOOLS_REPO/.build/release/apple-app-tools" auto-deploy verify --app glean-mac
fi
