#!/bin/bash
# Runs Apple's automatic accessibility audit on Crystal Set's screens and
# prints what it finds (see UITests/ for what's checked and how).
#
#   ./audit.sh ios     on a connected, unlocked iPhone (the test opens the
#                      app and moves through its tabs by itself)
#   ./audit.sh mac     on this Mac. The first time, macOS asks to let the
#                      test runner control the computer (Privacy & Security >
#                      Accessibility); turn that off again afterwards.
#
# Only the findings are printed, one "AUDIT:" line each, then a summary.
# The full log is saved to build/audit-<platform>.log.
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

PLATFORM="${1:-}"
case "$PLATFORM" in
  ios|mac) ;;
  *) echo "Usage: ./audit.sh ios   or   ./audit.sh mac" >&2; exit 2 ;;
esac

TEAM="${CRYSTAL_SET_TEAM:-}"
if [ -z "$TEAM" ] && [ -f ios-team.txt ]; then
  TEAM="$(tr -d '[:space:]' < ios-team.txt)"
fi
if [ -z "$TEAM" ]; then
  echo "No team ID. Put your 10-character Apple team ID in ios-team.txt in this folder." >&2
  exit 1
fi

if [ "$PLATFORM" = ios ]; then
  # The first connected iPhone, found the same way as in ios.sh.
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
  if [ -z "$DEVICE" ]; then
    echo "No iPhone found. Connect it with a cable, unlock it, and try again." >&2
    exit 1
  fi
  SCHEME="CrystalSet-iOS"; DESTINATION="id=$DEVICE"
  echo "Running the accessibility audit on your iPhone. Keep it unlocked; this takes a few minutes…"
else
  SCHEME="CrystalSet-macOS"; DESTINATION="platform=macOS"
  echo "Running the accessibility audit on this Mac. Crystal Set will open and switch tabs by itself; this takes a minute or two…"
fi

xcodegen generate --quiet
mkdir -p build
LOG="build/audit-$PLATFORM.log"

# `test` builds the app and the UI tests, installs both, and runs them.
# The run "fails" when the audit finds problems, so its exit status is
# ignored here; the summary below says what happened.
xcodebuild \
  -project CrystalSet.xcodeproj \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "build/$PLATFORM-tests" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  test > "$LOG" 2>&1 || true

# Copy the screenshots out of the test results, one PNG per screen audited.
SHOTS="build/audit-screenshots-$PLATFORM"
rm -rf "$SHOTS"; mkdir -p "$SHOTS"
RESULT="$(ls -td "build/$PLATFORM-tests"/Logs/Test/*.xcresult 2>/dev/null | head -1)"
if [ -n "$RESULT" ]; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS" >/dev/null 2>&1 || true
fi

# Each finding once (the runner can print a line twice), then the totals.
grep -E '^AUDIT: ' "$LOG" | awk '!seen[$0]++' || true
grep -E '^AUDIT SUMMARY|Executed [0-9]+ test|error:|\*\* TEST' "$LOG" | awk '!seen[$0]++' || true
echo "Full log: $(pwd)/$LOG"
echo "Screenshots: $(pwd)/$SHOTS"
