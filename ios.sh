#!/bin/bash
# Builds the iPhone and iPad version of Crystal Set.
#
#   ./ios.sh                   build only
#   ./ios.sh install           build, then install and open it on a device
#   ./ios.sh install ipad      ...on the iPad (any word from its name or
#   ./ios.sh install iphone       type: "ipad", "iphone", "scott's ipad"…)
#
# With no device named, it uses the first iPhone or iPad it finds and says
# which. Devices are found over a cable or, once paired, over Wi-Fi.
#
# Needs: Xcode, XcodeGen (brew install xcodegen), Xcode signed in to your
# Apple ID (Xcode > Settings > Accounts), and your team ID in ios-team.txt
# in this folder. Each iPhone or iPad needs Developer Mode on (Settings >
# Privacy & Security > Developer Mode); the setting appears once the device
# has been connected to this Mac by cable. Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.scott-h5.crystalset"
APP="build/ios/Build/Products/Release-iphoneos/CrystalSet.app"

case "${1:-}" in
  ""|install) ;;
  *) echo "Usage: ./ios.sh [install [ipad|iphone|device name]]" >&2; exit 2 ;;
esac
WANTED="${2:-}"

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

# Find the device: the one named, or else the first iPhone or iPad. Building
# for a particular device also registers it with your team, which a
# development build needs before it will run there.
#
# Why not insist on a "physical" device: an iPad that isn't fully set up for
# development yet doesn't report that at all, and was skipped. Simulators
# report "virtual", so leaving those out is enough.
LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
xcrun devicectl list devices --quiet --json-output "$LIST" >/dev/null 2>&1 || true
CHOICE="$(python3 -I -c '
import json, sys
wanted = sys.argv[2].lower()
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    props = d.get("deviceProperties", {})
    name = props.get("name", "")
    kind = hw.get("deviceType", "")
    if hw.get("platform") != "iOS" or hw.get("reality") == "virtual":
        continue
    if conn.get("tunnelState") == "unavailable":
        continue
    if wanted and wanted not in name.lower().replace("\u2019", "\x27") and wanted != kind.lower():
        continue
    # udid, name, Developer Mode status ("enabled", "disabled" or unknown)
    print(hw.get("udid") or d["identifier"], name, props.get("developerModeStatus") or "unknown", sep="\t")
    break
' "$LIST" "$WANTED")"
DEVICE="$(printf '%s' "$CHOICE" | cut -f1)"
DEVICE_NAME="$(printf '%s' "$CHOICE" | cut -f2)"
DEV_MODE="$(printf '%s' "$CHOICE" | cut -f3)"

if [ -n "$DEVICE" ]; then
  echo "Device: $DEVICE_NAME"
  if [ "$DEV_MODE" != "enabled" ] && [ "${1:-}" = "install" ]; then
    echo "Note: Developer Mode doesn't show as on for $DEVICE_NAME. If the install fails, turn it on:"
    echo "  Settings > Privacy & Security > Developer Mode, then restart the device and confirm."
  fi
fi

if [ -n "$DEVICE" ]; then
  DESTINATION="id=$DEVICE"
elif [ "${1:-}" = "install" ]; then
  echo "No ${WANTED:-iPhone or iPad} found. Connect it with a cable, unlock it, and try again." >&2
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
echo "Installed on $DEVICE_NAME."

# Open it. This fails if the iPhone is locked, which is harmless.
if xcrun devicectl device process launch --quiet --terminate-existing \
     --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "Opened Crystal Set."
else
  echo "Unlock $DEVICE_NAME and open Crystal Set from the Home Screen."
fi
