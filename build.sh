#!/bin/bash
# Builds the Mac version, "Crystal Set.app", into the build folder.
# (The iPhone version is built with ios.sh.)
#
#   bash build.sh            build only
#   bash build.sh install    build, then replace the copy in /Applications
#                            (quits the app first and reopens it if it was running)
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Crystal Set"
BUNDLE_ID="io.github.scott-h5.crystalset"
# Where xcodebuild puts the finished app.
APP="build/mac/Build/Products/Release/CrystalSet.app"
INSTALLED="/Applications/$APP_NAME.app"

case "${1:-}" in
  ""|install) ;;
  *) echo "Usage: bash build.sh [install]" >&2; exit 2 ;;
esac

# The Apple team that signs the app: from CRYSTAL_SET_TEAM if set, otherwise
# from ios-team.txt (the same file ios.sh uses; one team signs both versions).
TEAM="${CRYSTAL_SET_TEAM:-}"
if [ -z "$TEAM" ] && [ -f ios-team.txt ]; then
  TEAM="$(tr -d '[:space:]' < ios-team.txt)"
fi
if [ -z "$TEAM" ]; then
  echo "No team ID. Put your 10-character Apple team ID in ios-team.txt in this folder." >&2
  echo "It's shown on developer.apple.com/account under Membership details." >&2
  exit 1
fi

# Make the Xcode project from project.yml (see the notes at the top of that file).
xcodegen generate --quiet

# Build and sign with your team. -quiet prints only warnings and errors.
# The destination is "this Mac" (not "any Mac") so that Xcode registers this
# Mac with your team the first time: iCloud needs a development profile, and
# a Mac development profile lists the Macs it may run on.
# -allowProvisioningUpdates lets Xcode create the certificate and signing
# profile it needs, the first time and whenever they expire.
xcodebuild -quiet \
  -project CrystalSet.xcodeproj \
  -scheme CrystalSet-macOS \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath build/mac \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  build

echo "Built: $(pwd)/$APP"

if [ "${1:-}" != "install" ]; then
  echo "To build and install in Applications:  bash build.sh install"
  exit 0
fi

# Quit the app if it's running, so the new copy is the one that opens.
was_running=no
if pgrep -x CrystalSet >/dev/null; then
  was_running=yes
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x CrystalSet >/dev/null || break
    sleep 0.5
  done
  if pgrep -x CrystalSet >/dev/null; then
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
