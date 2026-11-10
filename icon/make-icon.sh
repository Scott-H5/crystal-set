#!/bin/bash
# Redraws Crystal Set's app icon and makes every size the Mac and iPhone need.
#
#   bash icon/make-icon.sh
#
# 1. icon/make-icon.swift draws the 1024-pixel pictures (see that file for the design).
# 2. sips (built into macOS) shrinks the Mac picture to each size macOS uses.
# 3. iconutil (also built in) packs those into macOS/AppIcon.icns.
#
# The iPhone needs only the one 1024-pixel picture; Xcode makes the smaller
# sizes when ios.sh builds. Run this again after changing the design, then
# rebuild with build.sh and ios.sh. Works from any folder.
set -euo pipefail
cd "$(dirname "$0")/.."

xcrun swift icon/make-icon.swift

# An ".iconset" is a folder of PNGs with names macOS expects: each size,
# plus a double-resolution "@2x" copy for Retina screens.
ICONSET="icon/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px icon/build/AppIcon-mac.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  double=$((px * 2))
  sips -z $double $double icon/build/AppIcon-mac.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o macOS/AppIcon.icns
echo "Wrote macOS/AppIcon.icns"
