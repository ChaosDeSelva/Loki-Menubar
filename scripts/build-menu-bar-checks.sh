#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_CHECK_APP="$LOKI_ROOT/build/local-qa/Loki Menu Bar Checks.app"
mkdir -p "$LOKI_CHECK_APP/Contents/MacOS" "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  -framework AppKit -framework ApplicationServices \
  "$LOKI_ROOT/native/MenuBarArranger.swift" "$LOKI_ROOT/native/MenuDiscovery.swift" \
  "$LOKI_ROOT/native/MenuBarSections.swift" "$LOKI_ROOT/native/MenuGeometry.swift" \
  "$LOKI_ROOT/native/MenuLabel.swift" "$LOKI_ROOT/native/ShelfEngine.swift" \
  "$LOKI_ROOT/tests/LiveMenuBarChecks.swift" -o "$LOKI_CHECK_APP/Contents/MacOS/LiveMenuBarChecks"
# The publisher's identity preserves Loki's existing grant; an unsigned harness refuses live input.
cat > "$LOKI_CHECK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LiveMenuBarChecks</string>
<key>CFBundleIdentifier</key><string>io.github.ChaosDeSelva.Loki</string>
<key>CFBundleName</key><string>Loki Menu Bar Checks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign "${LOKI_SIGN_IDENTITY:--}" --options runtime "$LOKI_CHECK_APP"
codesign --verify --strict "$LOKI_CHECK_APP"
printf 'Built %s\n' "$LOKI_CHECK_APP"
