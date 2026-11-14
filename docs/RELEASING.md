# Releasing Loki-Menubar

A release is a Developer ID signed, hardened runtime, notarized and stapled
`Loki.app`, shipped as a stapled DMG (manual installs) and a ZIP (Sparkle
updates), plus `SHA256SUMS`. Gatekeeper should open both without warnings.

No certificates, passwords, API keys or Sparkle private keys belong in this
repository. Everything secret lives in the publisher's login Keychain.

## One-time setup

1. **Developer ID Application certificate.** In the Apple Developer account
   (Certificates, Identifiers & Profiles) create a *Developer ID Application*
   certificate, or create it from Xcode > Settings > Accounts > Manage
   Certificates. Confirm it is in the login Keychain:

   ```sh
   security find-identity -v -p codesigning | grep 'Developer ID Application'
   ```

   Use the full quoted name (`Developer ID Application: Name (TEAMID)`) or its
   SHA-1 hash as `LOKI_SIGN_IDENTITY`.

2. **Notary credentials.** Store them once as a Keychain profile, using an
   app-specific password from appleid.apple.com (or an App Store Connect API
   key with `--key`, `--key-id`, `--issuer`):

   ```sh
   xcrun notarytool store-credentials loki-notary \
     --apple-id you@example.com --team-id TEAMID
   ```

   `notarytool` prompts for the password and keeps it in the Keychain.
   `loki-notary` is the value for `LOKI_NOTARY_PROFILE`.

3. **Sparkle EdDSA key.** The public key is `SUPublicEDKey` in
   `scripts/build.sh`. The matching private key is in the login Keychain under
   the account `Loki-Menubar`. Check it matches:

   ```sh
   bash scripts/prepare-sparkle.sh
   build/vendor/Sparkle/bin/generate_keys --account Loki-Menubar -p
   ```

   The output must equal `SUPublicEDKey`. Never generate a new key for an
   existing install base: installed copies would reject every future update.

## Entitlements

Loki ships no entitlements file. It is not sandboxed and uses no JIT,
unsigned executable memory, or library validation exceptions. Accessibility
and `CGEvent` posting are granted by the user through TCC, not by an
entitlement. Hardened runtime (`--options runtime`) is enabled by
`scripts/build.sh` whenever `LOKI_SIGN_IDENTITY` is set.

Sparkle 2.x requirements (sparkle-project.org/documentation/sandboxing) are
followed by `scripts/build.sh`: each nested component (`XPCServices/*.xpc`,
`Updater.app`, `Autoupdate`) is signed individually with hardened runtime,
then `Sparkle.framework`, then the app. `Downloader.xpc` is re-signed with
`--preserve-metadata=entitlements`. `--deep` is never used for signing (only
for `codesign --verify`).

## Release commands

1. Pick the version. In `scripts/build.sh`, increment `LOKI_BUILD_NUMBER`
   (`CFBundleVersion`, must grow for every published build, Sparkle compares
   it) and set `LOKI_RELEASE_LABEL` (artifact names and the GitHub tag, for
   example `0.1.0-alpha.7`). `LOKI_MARKETING_VERSION` is
   `CFBundleShortVersionString`. All three can also be overridden from the
   environment. `package.sh` and `notarize.sh` read the label back from the
   built app's `LokiReleaseLabel` key.

2. Build, sign, notarize, staple and package:

   ```sh
   export LOKI_SIGN_IDENTITY='Developer ID Application: Name (TEAMID)'
   export LOKI_NOTARY_PROFILE=loki-notary
   bash scripts/test.sh
   bash scripts/build.sh
   bash scripts/notarize.sh
   ```

   `notarize.sh` refuses a build that is not Developer ID signed with hardened
   runtime, notarizes and staples the app, runs `scripts/package.sh` to make
   and sign the DMG, notarizes and staples the DMG, rebuilds the ZIP from the
   stapled app, and writes `build/release/SHA256SUMS`. If Apple rejects a
   submission it prints the `notarytool log` and stops.

   `scripts/package.sh` on its own makes unnotarized artifacts and is only for
   local testing.

## Sign the Sparkle update and appcast

Use the ZIP for Sparkle; the DMG is for manual installs.

```sh
LABEL=0.1.0-alpha.7
mkdir -p build/feed
cp "build/release/Loki-Menubar-$LABEL-arm64.zip" build/feed/
cp docs/appcast.xml build/feed/appcast.xml
build/vendor/Sparkle/bin/generate_appcast \
  --account Loki-Menubar \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/ChaosDeSelva/Loki-Menubar/releases/download/v$LABEL/" \
  build/feed
```

`generate_appcast` signs the enclosure with the EdDSA key and, because the app
sets `SURequireSignedFeed`, signs the appcast itself. For a single archive,
`sign_update` prints the `sparkle:edSignature` and `length` attributes:

```sh
build/vendor/Sparkle/bin/sign_update --account Loki-Menubar "build/release/Loki-Menubar-$LABEL-arm64.zip"
```

Verify before publishing:

```sh
build/vendor/Sparkle/bin/sign_update --account Loki-Menubar --verify \
  "build/release/Loki-Menubar-$LABEL-arm64.zip" '<edSignature from the appcast>'
build/vendor/Sparkle/bin/sign_update --account Loki-Menubar --verify build/feed/appcast.xml
```

Copy `build/feed/appcast.xml` unchanged to `docs/appcast.xml`. Editing the
signed XML by hand invalidates it; regenerate instead. Upload the DMG, ZIP and
`SHA256SUMS` to the `v$LABEL` GitHub release before deploying the appcast.
See `UPDATES.md` for the remaining publish and upgrade test checklist.

## Verification

```sh
APP=build/Loki.app
DMG="build/release/Loki-Menubar-$LABEL-arm64.dmg"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'flags=|Authority=|TeamIdentifier'   # expect runtime, Developer ID
xcrun stapler validate "$APP"
spctl -a -vv -t exec "$APP"                  # expect: accepted, source=Notarized Developer ID

codesign --verify --strict --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"

(cd build/release && shasum -a 256 -c SHA256SUMS)
```

Finally, download the published DMG in a browser (so it carries the
quarantine attribute), open it, and launch Loki from `/Applications` on a
machine that has never run it: there must be no Gatekeeper prompt beyond the
standard "downloaded from the Internet" confirmation.
