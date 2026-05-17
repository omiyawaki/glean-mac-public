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

PLIST_ARG="$REPO/Resources/Info.plist"

swift run --package-path "$TOOLS_REPO" -c release apple-app-tools mac package \
    --config "$REPO/AppleAppBlueprint.yaml" \
    --binary "$BIN" \
    --plist "$PLIST_ARG" \
    "${RESOURCE_ARGS[@]}"

# SwiftPM emits target resource bundles next to the binary in .build/.
# Bundle.module's accessor expects the bundle alongside the .app — i.e.
# Glean.app/GleanMac_GleanMac.bundle, not inside Contents/Resources.
# Copy it explicitly so the app works on machines other than the one
# that built it.
SPM_BUNDLE="$REPO/.build/arm64-apple-macosx/$CONFIG/GleanMac_GleanMac.bundle"
if [[ -d "$SPM_BUNDLE" ]]; then
    rm -rf "$APP/GleanMac_GleanMac.bundle"
    cp -R "$SPM_BUNDLE" "$APP/GleanMac_GleanMac.bundle"
    # Bundle(path:) refuses to load a directory that lacks an Info.plist
    # on machines other than the build host (probably because SwiftPM's
    # own discovery cache is what makes the loose-directory form work
    # locally). Drop a minimal Info.plist so the bundle is valid for
    # Bundle(path:) on any machine.
    cat > "$APP/GleanMac_GleanMac.bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.miyawaki.glean-mac.resources</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
PLIST
fi

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
