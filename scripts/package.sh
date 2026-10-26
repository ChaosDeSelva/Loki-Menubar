#!/bin/bash
# Builds the DMG and ZIP release artifacts from an already built Loki.app.
# For a distributable release run scripts/notarize.sh instead; it notarizes
# and staples the app first, then calls this script, then notarizes the DMG.
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_APP="${LOKI_BUILD_DIR:-$LOKI_ROOT/build}/Loki.app"
LOKI_DEST="${1:-$LOKI_ROOT/build/release}"
test -d "$LOKI_APP" || { echo "Build Loki.app first: $LOKI_APP not found (run scripts/build.sh)." >&2; exit 1; }
LOKI_PLIST="$LOKI_APP/Contents/Info.plist"
LOKI_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LokiReleaseLabel' "$LOKI_PLIST" 2>/dev/null)" || {
  echo "LokiReleaseLabel missing from $LOKI_PLIST; rebuild with scripts/build.sh." >&2; exit 1; }
[[ "$LOKI_VERSION" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid LokiReleaseLabel: $LOKI_VERSION" >&2; exit 1; }
LOKI_DMG="$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.dmg"
LOKI_ZIP="$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.zip"
mkdir -p "$LOKI_DEST"
LOKI_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/loki-dmg.XXXXXX")"
trap 'rm -rf "$LOKI_STAGE"' EXIT
ditto "$LOKI_APP" "$LOKI_STAGE/Loki.app"
ln -s /Applications "$LOKI_STAGE/Applications"
printf '%s\n' 'Loki-Menubar preview' '' 'Drag Loki.app into Applications, launch it, then click its menu-bar rune.' 'Read release notes before enabling divider hiding.' > "$LOKI_STAGE/Install.txt"
hdiutil create -volname 'Loki' -srcfolder "$LOKI_STAGE" -ov -format UDZO "$LOKI_DMG"
if [[ -n "${LOKI_SIGN_IDENTITY:-}" && "$LOKI_SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$LOKI_SIGN_IDENTITY" --timestamp "$LOKI_DMG"
fi
rm -f "$LOKI_ZIP"
ditto -c -k --keepParent "$LOKI_APP" "$LOKI_ZIP"
echo "Packaged $LOKI_DMG"
echo "Packaged $LOKI_ZIP"
if [[ -z "${LOKI_FROM_NOTARIZE:-}" ]]; then
  echo 'These artifacts are not notarized. For a release, run scripts/notarize.sh (see docs/RELEASING.md).'
fi
