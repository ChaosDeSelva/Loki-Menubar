#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_BUILD="$LOKI_ROOT/build"
LOKI_APP="$LOKI_BUILD/Loki.app"
mkdir -p "$LOKI_APP/Contents/MacOS" "$LOKI_APP/Contents/Resources" "$LOKI_BUILD/module-cache"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$LOKI_BUILD/module-cache" \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon -framework ServiceManagement \
  "$LOKI_ROOT"/native/*.swift -o "$LOKI_APP/Contents/MacOS/Loki"
cat > "$LOKI_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Loki</string>
<key>CFBundleIdentifier</key><string>io.github.ChaosDeSelva.Loki</string>
<key>CFBundleName</key><string>Loki</string>
<key>CFBundleDisplayName</key><string>Loki</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleIconFile</key><string>Loki</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Loki-Menubar contributors</string>
</dict></plist>
PLIST
if [[ -n "${LOKI_BUNDLE_ID:-}" ]]; then
  [[ "$LOKI_BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'Invalid bundle identifier' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $LOKI_BUNDLE_ID" "$LOKI_APP/Contents/Info.plist"
fi
swiftc -module-cache-path "$LOKI_BUILD/module-cache" "$LOKI_ROOT/native/BrandMark.swift" "$LOKI_ROOT/scripts/Icon.swift" -o "$LOKI_BUILD/draw-icon"
"$LOKI_BUILD/draw-icon" "$LOKI_BUILD/Loki.iconset"
iconutil -c icns "$LOKI_BUILD/Loki.iconset" -o "$LOKI_APP/Contents/Resources/Loki.icns"
codesign --force --sign "${LOKI_SIGN_IDENTITY:--}" --options runtime "$LOKI_APP"
codesign --verify --strict "$LOKI_APP"
echo "Built $LOKI_APP"
