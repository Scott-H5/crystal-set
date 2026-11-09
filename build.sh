#!/bin/bash
# Builds "OTR Tuner.app" into the build folder.
#
#   bash build.sh            build only
#   bash build.sh install    build, then replace the copy in /Applications
#                            (quits the app first and reopens it if it was running)
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="OTR Tuner"
BUNDLE_ID="io.github.scott-h5.otrtuner"
APP="build/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

case "${1:-}" in
  ""|install) ;;
  *) echo "Usage: bash build.sh [install]" >&2; exit 2 ;;
esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "${ARCH}-apple-macos13.0" -sdk "$SDK" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/OTRTuner"

codesign --force --sign - "$APP" 2>/dev/null

echo "Built: $(pwd)/$APP"

if [ "${1:-}" != "install" ]; then
  echo "To build and install in Applications:  bash build.sh install"
  exit 0
fi

# Quit the app if it's running, so the new copy is the one that opens.
was_running=no
if pgrep -x OTRTuner >/dev/null; then
  was_running=yes
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x OTRTuner >/dev/null || break
    sleep 0.5
  done
  if pgrep -x OTRTuner >/dev/null; then
    echo "$APP_NAME didn't quit. Quit it, then run this again." >&2
    exit 1
  fi
fi

rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
echo "Installed: $INSTALLED"

if [ "$was_running" = yes ]; then
  open "$INSTALLED"
  echo "Reopened $APP_NAME"
fi
