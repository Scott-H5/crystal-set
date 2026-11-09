#!/bin/bash
# Builds the iPhone version of Crystal Set.
#
#   bash ios.sh            build only
#   bash ios.sh install    build, then install and open it on a connected iPhone
#
# Needs: Xcode, XcodeGen (brew install xcodegen), Xcode signed in to your
# Apple ID (Xcode > Settings > Accounts), and your team ID in ios-team.txt
# in this folder. The iPhone needs Developer Mode on (Settings > Privacy &
# Security > Developer Mode). Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.scott-h5.crystalset"
APP="build/ios/Build/Products/Release-iphoneos/CrystalSet.app"

case "${1:-}" in
  ""|install) ;;
  *) echo "Usage: bash ios.sh [install]" >&2; exit 2 ;;
esac

# The Apple team that signs the app: from CRYSTAL_SET_TEAM if set, otherwise
# from ios-team.txt. (That file isn't in git, so each person uses their own.)
TEAM="${CRYSTAL_SET_TEAM:-}"
if [ -z "$TEAM" ] && [ -f ios-team.txt ]; then
  TEAM="$(tr -d '[:space:]' < ios-team.txt)"
fi
if [ -z "$TEAM" ]; then
  echo "No team ID. Put your 10-character Apple team ID in ios-team.txt in this folder." >&2
  echo "It's shown in Xcode > Settings > Accounts, or on developer.apple.com/account." >&2
  exit 1
fi

# Find the first connected iPhone or iPad. Building for that particular
# iPhone also registers it with your team, which a free Personal Team needs
# before it can sign the app.
LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
xcrun devicectl list devices --quiet --json-output "$LIST" >/dev/null 2>&1 || true
DEVICE="$(python3 -I -c '
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" \
            and conn.get("tunnelState") != "unavailable":
        print(hw.get("udid") or d["identifier"]); break
' "$LIST")"

if [ -n "$DEVICE" ]; then
  DESTINATION="id=$DEVICE"
elif [ "${1:-}" = "install" ]; then
  echo "No iPhone found. Connect it with a cable, unlock it, and try again." >&2
  exit 1
else
  DESTINATION="generic/platform=iOS"
fi

# Make the Xcode project from project.yml.
xcodegen generate --quiet

# Build. -quiet prints only warnings and errors.
# -allowProvisioningUpdates lets Xcode create the signing profile it needs.
xcodebuild -quiet \
  -project CrystalSet.xcodeproj \
  -scheme CrystalSet-iOS \
  -configuration Release \
  -destination "$DESTINATION" \
  -derivedDataPath build/ios \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  build

echo "Built: $(pwd)/$APP"

if [ "${1:-}" != "install" ]; then
  echo "To build and install on your iPhone:  bash ios.sh install"
  exit 0
fi

xcrun devicectl device install app --quiet --device "$DEVICE" "$APP"
echo "Installed on your iPhone."

# Open it. This fails if the iPhone is locked, which is harmless.
if xcrun devicectl device process launch --quiet --terminate-existing \
     --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "Opened Crystal Set."
else
  echo "Unlock your iPhone and open Crystal Set from the Home Screen."
fi
