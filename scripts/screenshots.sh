#!/usr/bin/env bash
#
# Regenerate the README screenshots from the offline demo mode.
# Boots an iOS simulator, installs a demo build, and captures each screen.
#
#   ./scripts/screenshots.sh
#
set -euo pipefail

DEVICE="${DEVICE:-iPhone 15 Pro}"
DERIVED="${DERIVED:-build/screenshots-dd}"
SHOTS="docs/screenshots"
BUNDLE="com.noeron.app"

cd "$(dirname "$0")/.."
mkdir -p "$SHOTS"

echo "▸ Generating Xcode project"
xcodegen generate >/dev/null

echo "▸ Building Noeron (iOS Simulator)"
xcodebuild -project Noeron.xcodeproj -scheme Noeron_iOS \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Noeron.app"

UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | grep -oE '[0-9A-F-]{36}')
echo "▸ Booting $DEVICE ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
sleep 6
xcrun simctl install "$UDID" "$APP"

capture () { # <screen> <file>
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_NOERON_DEMO=1 SIMCTL_CHILD_NOERON_DEMO_SCREEN="$1" \
    xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 7
  xcrun simctl io "$UDID" screenshot "$SHOTS/$2" >/dev/null
  echo "  ✓ $SHOTS/$2"
}

echo "▸ Capturing screens"
capture graph    graph.png
capture overview overview.png
capture timeline timeline.png

echo "▸ Done. Shutting down simulator."
xcrun simctl shutdown "$UDID" 2>/dev/null || true
