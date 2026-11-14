#!/bin/bash
# TestFlight from the terminal: testers, the public link, and submitting
# builds for review, through the App Store Connect API (see tools/asc.swift).
#
#   ./asc.sh status                       latest builds and their review state
#   ./asc.sh testers                      who is in the Testers group
#   ./asc.sh add-tester EMAIL [FIRST LAST]
#   ./asc.sh remove-tester EMAIL
#   ./asc.sh link                         show the public link (link on [LIMIT], link off)
#   ./asc.sh submit ios|mac [BUILD]       newest build, or BUILD, to Beta App Review (asks first)
#
# Needs an App Store Connect API key (README: "TestFlight from the
# terminal"). Its settings live outside the project, in
# ~/.appstoreconnect/crystal-set.env, so they're never committed.
#
# Works from any folder.
set -euo pipefail
cd "$(dirname "$0")"

SETTINGS="$HOME/.appstoreconnect/crystal-set.env"
if [ ! -f "$SETTINGS" ]; then
  echo "No API settings at $SETTINGS. See \"TestFlight from the terminal\" in README.md." >&2
  exit 1
fi
# `set -a` exports every setting the file defines, so the tool can read them.
set -a; . "$SETTINGS"; set +a

# Compile the tool once, and again whenever its source changes. (Compiled,
# it starts instantly; run as a script, Swift takes several seconds.)
TOOL="build/asc"
if [ ! -x "$TOOL" ] || [ tools/asc.swift -nt "$TOOL" ]; then
  mkdir -p build
  xcrun swiftc -O -o "$TOOL" tools/asc.swift 2>&1 | grep -E "error" >&2 || true
  [ -x "$TOOL" ] || { echo "Couldn't build tools/asc.swift." >&2; exit 1; }
fi

exec "$TOOL" "$@"
