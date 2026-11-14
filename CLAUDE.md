# Loki-Menubar: notes for agents

Swift/AppKit menu-bar utility. `origin` is `github.com/ChaosDeSelva/Loki-Menubar`
(GitHub, not a local bare repo). Releases, the Sparkle feed (`docs/appcast.xml`) and
the download page (`docs/index.html`, GitHub Pages) all live in that repo.

## Where things stand (November 2026)

- Latest release: **v0.1.0-alpha.7** (build 12), a notarized pre-release with DMG, ZIP
  and SHA256SUMS. The appcast offers it and its ZIP signature verifies. CI is green.
- Tests: `bash scripts/test.sh` runs three suites: `tests/TestMain.swift` (pure logic),
  `tests/VisibilityBridgeTests.m` (Objective-C bridge) and `tests/ControllerTests.swift`
  (VisibilityController driven through a fake allowlist).
- Confirmed on macOS 27.0.1 hardware: hiding a chosen app while everything else
  stays visible, and Reveal All bringing it back.
- Confirmed on macOS 26.5.1, notched 14" MacBook Pro: the divider backend hides chosen
  icons, and hover reveal re-hides after the delay. Un-hiding is not confirmed: the one
  icon tried was behind the notch and could not be moved (see below).
- **Known gap on notched displays:** revealed icons are drawn left of the divider, so
  past the first few they land behind the notch. They can't be seen or dragged back
  from there. The likely fix is a panel under the menu bar that shows hidden icons.
- **Not yet verified on hardware:** on macOS 27, an app launched while icons are hidden,
  Option-click reveal and the mic/camera pause; macOS 14 to 25; multiple displays, sleep
  and wake. `ROADMAP.md` lists this work first.

## How hiding works (two backends)

- **macOS 14 to 26, the divider backend:** an `NSStatusItem` divider is widened to
  10,000 pt to push icons off-screen. Icons are moved across the divider with
  synthesized Command-drags (`native/MenuBarArranger.swift`). The user picks the
  hidden icons from a list. There is no drag bar to place by hand.
- **macOS 27, the allowlist backend:** the divider trick no longer works because
  status items wider than about half the screen are dropped. Loki instead uses the
  private `MenuBarClientCore` assessment-mode assertion (`nativeBridge/`,
  `native/MenuBarVisibility.swift`). It allows every installed and running app except
  the hidden ones, replacing the assertion make-before-break.
- Pure decision logic lives in `native/MenuBarSections.swift`. Keep it AppKit-free and
  fully covered.

## Gotchas that cost real time

- On macOS 27, **Loki must run from `/Applications`**. A copy anywhere else hides its
  own icon, and the controller refuses to hide outside Applications.
- **An app missing from the allowlist when the assertion is made stays hidden.**
  That is why the allowlist covers every installed bundle, not just running apps.
- Ad-hoc rebuilds change the code signature and silently break the Accessibility
  grant. Fix it with `tccutil reset Accessibility io.github.ChaosDeSelva.Loki`, or
  test with a Developer ID build.
- Divider backend, measured on macOS 26.5: a synthesized Command-drag settles about one
  slot short of where it is released. Release well past the divider
  (`MenuBarSections.dropOvershoot`). On a notched display, revealed positions are out of
  order, so read which side an icon is on only while the divider is collapsed.
- macOS 27 status-item clicks carry no modifier flags. Read `NSEvent.modifierFlags`
  instead.

## Releasing

Follow `docs/RELEASING.md`. On the release Mac, the signing identity, the notarytool
keychain profile `loki-notary` (an App Store Connect API key) and the Sparkle EdDSA
key (keychain account `Loki-Menubar`) are set up. Other Macs lack them, so their
builds are ad-hoc signed. Bump `LOKI_BUILD_NUMBER`
and `LOKI_RELEASE_LABEL` in `scripts/build.sh`. Never commit keys.
