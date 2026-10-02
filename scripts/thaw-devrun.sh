#!/usr/bin/env bash
# Builds Thaw and installs it as /Applications/Thaw Debug.app
# (com.stonerl.Thaw.debug), next to any released Thaw.
#
# macOS 27 attributes a status item to its app only when the app runs from
# /Applications. Run from DerivedData, Thaw's own icon vanishes on hide.
#
# Diagnostic logging is off in Release builds. To turn it on:
#   defaults write com.stonerl.Thaw.debug EnableDiagnosticLogging -bool true
#
# Usage:
#   ./scripts/thaw-devrun.sh                  # Release
#   ./scripts/thaw-devrun.sh --debug          # Debug, for the debugger
#   ./scripts/thaw-devrun.sh --skip-packages  # skip package resolution
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Thaw.xcodeproj"
SCHEME="Thaw"
CONFIG="Release"
APP_NAME="Thaw Debug"
DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="com.stonerl.Thaw.debug"
SKIP_PACKAGES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug" ;;
        --release) CONFIG="Release" ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        -h | --help)
            awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# The suffixes rename the app, its XPC service and the controls extension.
BUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -destination 'platform=macOS'
    -onlyUsePackageVersionsFromResolvedFile
    -skipPackageUpdates
    THAW_BUNDLE_ID_SUFFIX=.debug
    "THAW_PRODUCT_NAME_SUFFIX= Debug"
)

# Matches by install path so a released Thaw is left running.
quit_running_app() {
    pgrep -f "$DEST/" >/dev/null 2>&1 || return 0

    say "Quitting running '$APP_NAME'…"
    # Backgrounded so an app that hangs on quit cannot stall the script.
    (osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1) &

    for _ in {1..8}; do
        pgrep -f "$DEST/" >/dev/null 2>&1 || return 0
        sleep 0.5
    done

    say "Force-killing leftover '$APP_NAME' processes…"
    pkill -9 -f "$DEST/" 2>/dev/null || true
    sleep 1
}

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    say "Resolving Swift packages…"
    xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"
fi

say "Building $CONFIG ($BUNDLE_ID)…"
xcodebuild "${BUILD_ARGS[@]}" build

PRODUCTS_DIR=$(xcodebuild "${BUILD_ARGS[@]}" -showBuildSettings 2>/dev/null |
    awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP="$PRODUCTS_DIR/$APP_NAME.app"
[[ -d "$APP" ]] || {
    echo "Build product not found: $APP" >&2
    exit 1
}

quit_running_app

say "Installing to ${DEST}…"
rm -rf "$DEST"
mv "$APP" "$DEST"

say "Launching…"
open "$DEST"
say "Running '$APP_NAME' ($CONFIG). First launch: grant Accessibility and Screen Recording."
if [[ "$CONFIG" == "Release" ]]; then
    say "Diagnostic logging is off in Release. Enable with:"
    printf '      defaults write %s EnableDiagnosticLogging -bool true\n' "$BUNDLE_ID"
fi
