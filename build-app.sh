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
