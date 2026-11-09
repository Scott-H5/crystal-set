#!/bin/bash
# Builds "OTR Tuner.app" into the build folder. Run:  bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OTR Tuner.app"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "${ARCH}-apple-macos13.0" -sdk "$SDK" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/OTRTuner"

codesign --force --sign - "$APP"

echo "Built: $(pwd)/$APP"
echo "To install:  cp -R \"$APP\" /Applications/"
