#!/bin/bash
# Notarizes, staples and packages a Developer ID signed build/Loki.app.
#
# Required environment:
#   LOKI_SIGN_IDENTITY   Developer ID Application identity (name or SHA-1),
#                        the same one scripts/build.sh signed the app with.
#   LOKI_NOTARY_PROFILE  Keychain profile created once with
#                        `xcrun notarytool store-credentials`.
# Optional:
#   LOKI_BUILD_DIR       Build directory (default: build).
#   LOKI_NOTARY_TIMEOUT  notarytool --wait timeout (default: 1h).
#   $1                   Release output directory (default: build/release).
#
# No credentials are read or stored here; notarytool reads them from the
# login Keychain profile. See docs/RELEASING.md.
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_BUILD="${LOKI_BUILD_DIR:-$LOKI_ROOT/build}"
LOKI_APP="$LOKI_BUILD/Loki.app"
LOKI_DEST="${1:-$LOKI_ROOT/build/release}"
LOKI_NOTARY_TIMEOUT="${LOKI_NOTARY_TIMEOUT:-1h}"

fail() { echo "notarize.sh: $*" >&2; exit 1; }

[[ -n "${LOKI_SIGN_IDENTITY:-}" && "$LOKI_SIGN_IDENTITY" != "-" ]] ||
  fail 'LOKI_SIGN_IDENTITY must name a Developer ID Application identity (ad-hoc builds cannot be notarized).'
[[ -n "${LOKI_NOTARY_PROFILE:-}" ]] ||
  fail 'LOKI_NOTARY_PROFILE must name a keychain profile created with: xcrun notarytool store-credentials'
xcrun --find notarytool >/dev/null 2>&1 || fail 'xcrun notarytool not found; install Xcode or the Command Line Tools.'
xcrun --find stapler >/dev/null 2>&1 || fail 'xcrun stapler not found; install Xcode or the Command Line Tools.'
test -d "$LOKI_APP" || fail "$LOKI_APP not found. Build it first with LOKI_SIGN_IDENTITY set: bash scripts/build.sh"

LOKI_WORK="$(mktemp -d "${TMPDIR:-/tmp}/loki-notary.XXXXXX")"
trap 'rm -rf "$LOKI_WORK"' EXIT

# Refuse anything that is not Developer ID signed with hardened runtime.
require_runtime() {
  local target="$1" info
  info="$(codesign -dvv "$target" 2>&1)" || fail "$target is not code signed."
  grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$info" ||
    fail "$target is not signed with hardened runtime (expected flags=0x10000(runtime)). Rebuild with LOKI_SIGN_IDENTITY set."
  grep -q '^Authority=Developer ID Application' <<<"$info" ||
    fail "$target is not signed with a Developer ID Application certificate."
}

# Submits a file, waits, and prints the notary log on any non-Accepted result.
notarize() {
  local file="$1" name result id status
  name="$(basename "$file")"
  result="$LOKI_WORK/$name.submit.json"
  echo "Submitting $name for notarization (this can take several minutes)..."
  if ! xcrun notarytool submit "$file" --keychain-profile "$LOKI_NOTARY_PROFILE" \
      --wait --timeout "$LOKI_NOTARY_TIMEOUT" --output-format json >"$result"; then
    cat "$result" >&2 || true
  fi
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  [[ -n "$id" ]] || fail "notarytool did not return a submission id for $name (check the keychain profile and network)."
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization of $name finished with status '${status:-unknown}' (submission $id). Log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$LOKI_NOTARY_PROFILE" >&2 || true
    fail "notarization failed for $name."
  fi
  echo "Notarization accepted for $name (submission $id)."
}

LOKI_FRAMEWORK="$LOKI_APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for LOKI_TARGET in "$LOKI_FRAMEWORK"/XPCServices/*.xpc "$LOKI_FRAMEWORK"/Updater.app "$LOKI_FRAMEWORK"/Autoupdate "$LOKI_APP"; do
  require_runtime "$LOKI_TARGET"
done
codesign --verify --deep --strict --verbose=2 "$LOKI_APP"

# 1. Notarize and staple the app.
ditto -c -k --keepParent "$LOKI_APP" "$LOKI_WORK/Loki.zip"
notarize "$LOKI_WORK/Loki.zip"
xcrun stapler staple "$LOKI_APP"
xcrun stapler validate "$LOKI_APP"
spctl -a -vv -t exec "$LOKI_APP"

# 2. Package the stapled app, then notarize and staple the signed DMG.
LOKI_FROM_NOTARIZE=1 LOKI_SIGN_IDENTITY="$LOKI_SIGN_IDENTITY" bash "$LOKI_ROOT/scripts/package.sh" "$LOKI_DEST"
LOKI_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LokiReleaseLabel' "$LOKI_APP/Contents/Info.plist")"
LOKI_DMG="$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.dmg"
LOKI_ZIP="$LOKI_DEST/Loki-Menubar-$LOKI_VERSION-arm64.zip"
test -f "$LOKI_DMG" || fail "package.sh did not produce $LOKI_DMG"
codesign --verify --strict --verbose=2 "$LOKI_DMG" || fail "$LOKI_DMG is not signed."
notarize "$LOKI_DMG"
xcrun stapler staple "$LOKI_DMG"
xcrun stapler validate "$LOKI_DMG"
spctl -a -vv -t open --context context:primary-signature "$LOKI_DMG"

# 3. Rebuild the Sparkle ZIP from the stapled app and write checksums last.
rm -f "$LOKI_ZIP"
ditto -c -k --keepParent "$LOKI_APP" "$LOKI_ZIP"
(cd "$LOKI_DEST" && shasum -a 256 "$(basename "$LOKI_DMG")" "$(basename "$LOKI_ZIP")" >SHA256SUMS)
echo "Release artifacts in $LOKI_DEST:"
cat "$LOKI_DEST/SHA256SUMS"
echo 'Next: sign the ZIP and appcast with Sparkle (docs/RELEASING.md).'
