# Loki-Menubar

A little order. A little mischief. An original Swift/AppKit menu-bar utility for macOS, with a searchable shelf, favorites, and Nordic-inspired profiles.

[Download & installation](https://chaosdeselva.github.io/Loki-Menubar/) · [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases) · [Compatibility](COMPATIBILITY.md)

## Release status

**0.1.0-alpha.5 is an early preview.** Apple Silicon; macOS 14 or later. Release checks ran on macOS 27.0.1. Earlier macOS versions and notched MacBooks are not yet verified. See the explicit feature gaps below before installing.

## What is included

- A menu-bar dropdown, separate from the explicitly opened settings window; no Dock icon or launch-time window.
- Search, arrow-key navigation, Return to open, favorites, and drag ordering within Loki’s shelf.
- Separate sources for real menu extras and running-application shortcuts.
- Three renameable realms with independent favorites, order, and custom groups. Open Groups to create, rename, or remove categories such as Development, Meetings, or Home. Right-click a row to assign its group. Renaming retains assignments; removing a group returns items to Ungrouped.
- Menu discovery restricted to Accessibility menu-extra trees, excluding the Apple/File/Edit trees.
- Opening an item closes Loki first, resolves its accessible position, and posts a normal mouse click off the UI thread. Stale/unpositioned items fail with an explanation.
- An explicit close button, Escape, outside-click dismissal, and Control–Option–L to summon/toggle the shelf.
- App-based icon hiding on macOS 27 and an experimental divider on macOS 14–26; hover reveal, delayed rehide, and reveal-all recovery.
- Launch at login, three accent colors, local preferences, and preservation of corrupted settings files.
- CLI commands for the shelf, settings, reveal-all, and privacy-limited diagnostics.
- No analytics, accounts, or screen capture. macOS 27 hiding uses an undocumented system framework. Sparkle is the bundled update dependency; automatic checks are opt-in.

## Install

Download the Apple Silicon DMG from [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases), open it, and drag **Loki.app** into **Applications**. Launch Loki, then click its rune icon in the menu bar. Use the expand button to open the main window.

App shortcuts do not need Accessibility. Menu extras do: in **Menu items**, choose **Allow Accessibility** and enable the installed app in System Settings. A previous development build may have a different bundle identifier and permission entry; the public release uses `io.github.ChaosDeSelva.Loki`.

## Tuck icons on macOS 27

1. Open Loki’s full window and select **Menu bar**.
2. Select the apps whose icons you want tucked away. Choices are saved in the current realm.
3. Click **Tuck icons**. Loki closes its window; move away from the menu bar and wait for the selected delay.
4. Hover near the menu bar to reveal, or use **Reveal All Menu Bar Items** from Loki’s menu.

All icons belonging to an app hide together across every display. Apple system controls and Loki are included in the allowlist. This mode uses the installed MenuBarClientCore framework, an undocumented interface that may change with an OS update. If the expected interface is absent, hiding stays disabled. Hiding starts only when you request it, never automatically at launch.

## Tuck icons on macOS 14–26 (compatibility preview)

1. Open **Menu bar → Show divider**.
2. Hold Command and drag the filter-shaped divider to the **left** of Loki’s rune icon.
3. Command-drag the icons you want tucked away to the left of that divider.
4. Choose **Tuck icons** and move the pointer away from the menu bar.
5. Hover near the top of a display to reveal. Open Loki or choose **Reveal All Menu Bar Items** to recover.

The divider changes the width of an ordinary `NSStatusItem`. macOS owns placement; some icons cannot be moved. On macOS 14–26 it remains an experimental feature, not a qualified production layout. Hiding never starts automatically at launch. Display changes, sleep, and quitting stop it; Space changes reveal icons. Rehide waits while a popup, mouse press, or Command-drag is detected. **Reveal All** removes the divider entirely.

## Current limitations

No always-hidden tier, automatic physical-icon sorting, per-display layouts, icon image replication below a notch, custom global shortcut editor, spacing/tint/shape customization of the system bar, or background physical-layout automation. Groups organize the shelf. Realms also store app-hiding selections on macOS 27; switching realms reveals everything until you explicitly tuck again. Hidden/notch-obscured items must first be visible before Loki can click them. Some apps expose incomplete Accessibility labels or no position. Multi-monitor and full-screen behavior needs broader verification.

Loki is an independently developed utility. Its supported capabilities and remaining work are documented in the compatibility ledger.

## Build from source

Requires Apple Silicon, Xcode command-line tools, and Swift. The first build downloads the checksum-pinned Sparkle framework from its official release.

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Loki.app
```

The build defaults to an ad-hoc local signature. For a Developer ID build:

```sh
LOKI_SIGN_IDENTITY='Developer ID Application: Your Organization (TEAMID)' bash scripts/build.sh
```

Signing credentials are external to the repository. `LOKI_BUNDLE_ID` can override the bundle identifier for local development. Do not publish private certificates, keychain profiles, local preferences, or raw diagnostic logs.

## Command line

With the installed app running:

```sh
/Applications/Loki.app/Contents/MacOS/Loki --shelf
/Applications/Loki.app/Contents/MacOS/Loki --settings
/Applications/Loki.app/Contents/MacOS/Loki --reveal-all
/Applications/Loki.app/Contents/MacOS/Loki --status
```

`--diagnose` runs a standalone count-only discovery report. It contains no menu titles, file names, app list, or preferences. The CLI uses local notifications, not a network listener.

## Data and uninstall

Preferences live in `~/Library/Application Support/Loki/preferences.json`. They contain realm names, saved item identifiers, group assignments, and preferences. There is no cloud sync. See [PRIVACY.md](PRIVACY.md).

To uninstall: disable launch at login, quit Loki (which releases hiding and removes any divider), then move Loki.app to Trash. Optionally remove the preferences folder and the Loki Accessibility entry in System Settings. Other apps and their data are not removed.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Code and vector artwork are under [MIT](LICENSE). The folded-rune design was developed with AI-assisted concept exploration and recreated as vector paths; no third-party logo artwork is included. No trademark clearance is implied.

See [the roadmap](ROADMAP.md) for prioritized improvements and release-quality criteria.

### Alpha 3 fixes

Compact popup controls, consistent form heights, group deletion confirmation and session undo, improved system-menu labels, and signed in-app updates. Automatic update checks are opt-in in Settings.

**macOS 27:** app-selection hiding replaces the old divider. This candidate has passed build and lifecycle checks, but visual hide/reveal and forced-process-death recovery are still release gates. The divider remains experimental on macOS 14–26.
