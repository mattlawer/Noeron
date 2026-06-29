#!/usr/bin/env bash
#
# Generate the macOS README screenshots from the offline demo mode.
# Run this on your Mac (interactively) — it needs Screen Recording permission for
# your terminal the first time (System Settings → Privacy & Security → Screen
# Recording), which can't be granted from a headless/sandbox session.
#
#   ./scripts/screenshots-macos.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="${DERIVED:-build/screenshots-macos-dd}"
SHOTS="docs/screenshots"
mkdir -p "$SHOTS"

echo "▸ Building Noeron (macOS)"
xcodegen generate >/dev/null
xcodebuild -project Noeron.xcodeproj -scheme Noeron_macOS -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null
BIN="$DERIVED/Build/Products/Debug/Noeron.app/Contents/MacOS/Noeron"

winid () { # prints the Noeron window id
  cat > /tmp/_noeron_winid.swift <<'SWIFT'
import CoreGraphics; import Foundation
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String:Any]] ?? []
for w in l where (w[kCGWindowOwnerName as String] as? String) == "Noeron" {
  if let n = w[kCGWindowNumber as String] as? Int,
     let b = w[kCGWindowBounds as String] as? [String:Any],
     let h = b["Height"] as? Double, h > 200 { print(n); break }
}
SWIFT
  swift /tmp/_noeron_winid.swift 2>/dev/null | head -1
}

capture () { # <screen> <file>
  NOERON_DEMO=1 NOERON_DEMO_SCREEN="$1" "$BIN" >/dev/null 2>&1 &
  local pid=$!; sleep 5
  local id; id=$(winid)
  if [ -n "$id" ]; then screencapture -o -x -l"$id" "$SHOTS/$2" && echo "  ✓ $SHOTS/$2"
  else echo "  ✗ could not find window"; fi
  kill "$pid" 2>/dev/null || true
}

echo "▸ Capturing (grant Screen Recording permission if prompted)"
capture graph    graph-macos.png
capture overview overview-macos.png
echo "▸ Done."
