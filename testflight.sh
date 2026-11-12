#!/bin/bash
# Uploads a new build of Crystal Set to App Store Connect, for TestFlight.
#
#   ./testflight.sh ios      the iPhone (and iPad) version
#   ./testflight.sh mac      the Mac version
#
# Both are the same App Store Connect app (the same bundle ID), so their
# builds appear side by side in its TestFlight tab.
#
# What it does, in two steps:
#   1. "Archive": a Release build signed for distribution, saved in
#      build/archives. The first time, Xcode creates your Apple Distribution
#      certificate and an App Store provisioning profile (and, for the Mac,
#      a Mac Installer Distribution certificate, since Mac apps are uploaded
#      as an installer package).
#   2. "Export" with the upload option: xcodebuild sends the archive to App
#      Store Connect, signed in as the Apple ID in Xcode > Settings >
#      Accounts. No App Store Connect API key is needed.
#
# Each upload gets a new build number, the date and time, such as
# 202611121430, because App Store Connect refuses a build number it has seen
# before. The version people see (1.0) is MARKETING_VERSION in project.yml.
#
# After the upload, Apple processes the build (usually 5 to 30 minutes) and
# emails you. It then appears in the app's TestFlight tab in App Store Connect.
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
  ios) SCHEME="CrystalSet-iOS"; DESTINATION="generic/platform=iOS" ;;
  mac) SCHEME="CrystalSet-macOS"; DESTINATION="generic/platform=macOS" ;;
  *) echo "Usage: ./testflight.sh ios   or   ./testflight.sh mac" >&2; exit 2 ;;
esac

# The Apple team, as in build.sh and ios.sh.
TEAM="${CRYSTAL_SET_TEAM:-}"
if [ -z "$TEAM" ] && [ -f ios-team.txt ]; then
  TEAM="$(tr -d '[:space:]' < ios-team.txt)"
fi
if [ -z "$TEAM" ]; then
  echo "No team ID. Put your 10-character Apple team ID in ios-team.txt in this folder." >&2
  exit 1
fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ARCHIVE="build/archives/$SCHEME-$BUILD_NUMBER.xcarchive"

# The export settings, written fresh each time so they always use your team.
# "app-store-connect" signs for TestFlight and the App Store; "upload" sends
# it straight to App Store Connect instead of saving a file.
OPTIONS_DIR="$(mktemp -d)"
OPTIONS="$OPTIONS_DIR/ExportOptions.plist"
trap 'rm -rf "$OPTIONS_DIR"' EXIT
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

xcodegen generate --quiet

echo "Archiving $SCHEME, build $BUILD_NUMBER…"
xcodebuild -quiet \
  -project CrystalSet.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

echo "Uploading to App Store Connect…"
# The upload prints a "Progress …%" line every second or so; leave those
# out, so a screen reader doesn't have to read dozens of them. Errors and
# "Upload succeeded" still come through. (`|| true` stops grep from counting
# as a failure when it has nothing left to show; a failed upload still stops
# the script, because `set -o pipefail` reports xcodebuild's error.)
xcodebuild -quiet \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "build/archives/export-$BUILD_NUMBER" \
  -allowProvisioningUpdates 2>&1 \
  | { grep -vE 'Progress [0-9]+%|IDESchemeActionsInvocationRecord|IDEDistributionLogging' || true; }

echo "Uploaded build $BUILD_NUMBER. Apple emails you when it has been processed;"
echo "it then appears in App Store Connect under your app's TestFlight tab."
