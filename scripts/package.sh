#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_APP="$LOKI_ROOT/build/Loki.app"
LOKI_DEST="${1:-$LOKI_ROOT/build/release}"
LOKI_VERSION="0.1.0-alpha.1"
test -d "$LOKI_APP" || { echo 'Build Loki.app first.' >&2; exit 1; }
mkdir -p "$LOKI_DEST"
LOKI_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/loki-dmg.XXXXXX")"
trap 'rm -rf "$LOKI_STAGE"' EXIT
ditto "$LOKI_APP" "$LOKI_STAGE/Loki.app"
ln -s /Applications "$LOKI_STAGE/Applications"
printf '%s\n' 'Loki-Menubar preview' '' 'Drag Loki.app into Applications, launch it, then click its menu-bar rune.' 'Read release notes before enabling divider hiding.' > "$LOKI_STAGE/Install.txt"
hdiutil create -volname 'Loki' -srcfolder "$LOKI_STAGE" -ov -format UDZO "$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.dmg"
if [[ -n "${LOKI_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$LOKI_SIGN_IDENTITY" --timestamp "$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.dmg"
fi
ditto -c -k --keepParent "$LOKI_APP" "$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.zip"
echo 'Notarize/staple the app before packaging; notarize/staple the DMG afterward. Generate checksums last.'
