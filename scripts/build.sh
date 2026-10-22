#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_BUILD="${LOKI_BUILD_DIR:-$LOKI_ROOT/build}"
LOKI_APP="$LOKI_BUILD/Loki.app"
bash "$LOKI_ROOT/scripts/prepare-sparkle.sh"
LOKI_SIGN_OPTIONS=(--force --sign "${LOKI_SIGN_IDENTITY:--}")
if [[ "${LOKI_SIGN_IDENTITY:--}" != "-" ]]; then
  LOKI_SIGN_OPTIONS+=(--options runtime --timestamp)
fi
mkdir -p "$LOKI_APP/Contents/Frameworks" "$LOKI_APP/Contents/MacOS" "$LOKI_APP/Contents/Resources" "$LOKI_BUILD/module-cache"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$LOKI_BUILD/module-cache" \
  -F "$LOKI_ROOT/build/vendor/Sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
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
<key>CFBundleVersion</key><string>6</string>
<key>SUFeedURL</key><string>https://chaosdeselva.github.io/Loki-Menubar/appcast.xml</string>
<key>SUPublicEDKey</key><string>lQmA4X8FRIxdccivd/2WVfXK6Pk9X9PIzoiV4H5MWso=</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
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
ditto "$LOKI_ROOT/build/vendor/Sparkle/Sparkle.framework" "$LOKI_APP/Contents/Frameworks/Sparkle.framework"
# Sign nested executable bundles before the framework and host app.
LOKI_FRAMEWORK="$LOKI_APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for LOKI_NESTED in "$LOKI_FRAMEWORK"/XPCServices/*.xpc "$LOKI_FRAMEWORK"/Updater.app "$LOKI_FRAMEWORK"/Autoupdate; do
  codesign "${LOKI_SIGN_OPTIONS[@]}" "$LOKI_NESTED"
done
codesign "${LOKI_SIGN_OPTIONS[@]}" "$LOKI_APP/Contents/Frameworks/Sparkle.framework"
cp "$LOKI_ROOT/LICENSE" "$LOKI_APP/Contents/Resources/LICENSE.txt"
cp "$LOKI_ROOT/build/vendor/Sparkle/LICENSE" "$LOKI_APP/Contents/Resources/Sparkle-LICENSE.txt"
codesign "${LOKI_SIGN_OPTIONS[@]}" "$LOKI_APP"
codesign --verify --deep --strict "$LOKI_APP"
echo "Built $LOKI_APP"
