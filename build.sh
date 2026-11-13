#!/bin/zsh
# Build NuimoBar and assemble the .app bundle.
# Usage: ./build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")"

# Command Line Tools' macOS 27 SDK ships SwiftUI @State as a macro whose
# plugin only comes with Xcode, so build against the 26.5 SDK when present.
OLD_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
if [[ -d "$OLD_SDK" ]]; then export SDKROOT="$OLD_SDK"; fi

CONFIG=release
swift build -c "$CONFIG"

APP="build/NuimoBar.app"
pkill -x NuimoBar 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/NuimoBar" "$APP/Contents/MacOS/NuimoBar"
cp Info.plist "$APP/Contents/Info.plist"

# Bluetooth and Accessibility grants are bound to the code signature. The
# local self-signed "ForgeShot Dev" identity keeps them across rebuilds;
# ad-hoc signing is the fallback (macOS re-prompts after every rebuild).
if security find-certificate -c "ForgeShot Dev" >/dev/null 2>&1; then
    IDENTITY="ForgeShot Dev"
else
    IDENTITY="-"
    echo "warning: 'ForgeShot Dev' identity not found; ad-hoc signing (permissions re-prompt after rebuilds)"
fi
codesign --force --sign "$IDENTITY" --identifier co.theforge.NuimoBar "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--run" ]]; then
    open "$APP"
fi
