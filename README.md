# Loki-Menubar

A little order. A little mischief. An original Swift/AppKit menu-bar utility for macOS, with a searchable shelf, favorites, and Nordic-inspired profiles.

[Download & installation](https://chaosdeselva.github.io/Loki-Menubar/) · [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases) · [Compatibility](COMPATIBILITY.md)

## Release status

**0.1.0-alpha.1 is an early preview.** Apple Silicon; macOS 14 or later. Release checks ran on macOS 27.0.1. Earlier macOS versions and notched MacBooks are not yet verified. See the explicit feature gaps below before installing.

## What is included

- A menu-bar dropdown, separate from the explicitly opened settings window; no Dock icon or launch-time window.
- Search, arrow-key navigation, Return to open, favorites, and drag ordering within Loki’s shelf.
- Separate sources for real menu extras and running-application shortcuts.
- Three renameable realms with independent favorites, order, and Work/Personal/System groups. Right-click a row to assign its group.
- Menu discovery restricted to Accessibility menu-extra trees, excluding the Apple/File/Edit trees.
- Opening an item closes Loki first, resolves its accessible position, and posts a normal mouse click off the UI thread. Stale/unpositioned items fail with an explanation.
- An explicit close button, Escape, outside-click dismissal, and Control–Option–L to summon/toggle the shelf.
- A **compatibility-preview divider** for tucking icons; hover reveal, delayed rehide, and reveal-all recovery.
- Launch at login, three accent colors, local preferences, and preservation of corrupted settings files.
- CLI commands for the shelf, settings, reveal-all, and privacy-limited diagnostics.
- No analytics, accounts, third-party runtime dependencies, screen capture, private frameworks, or automatic downloads.

## Install

Download the Apple Silicon DMG from [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases), open it, and drag **Loki.app** into **Applications**. Launch Loki, then click its rune icon in the menu bar. Use the expand button to open the main window.

App shortcuts do not need Accessibility. Menu extras do: in **Menu items**, choose **Allow Accessibility** and enable the installed app in System Settings. A previous development build may have a different bundle identifier and permission entry; the public release uses `io.github.ChaosDeSelva.Loki`.

## Tuck icons (compatibility preview)

1. Open **Menu bar → Show divider**.
2. Hold Command and drag the `│` divider to the **left** of Loki’s rune icon.
3. Command-drag the icons you want tucked away to the left of that divider.
4. Choose **Tuck icons** and move the pointer away from the menu bar.
5. Hover near the top of a display to reveal. Open Loki or choose **Reveal All Menu Bar Items** to recover.

The divider changes the width of an ordinary `NSStatusItem`. macOS owns placement; some icons cannot be moved. The preview does not implement a private macOS 27 assessment-mode workaround. Visual hiding across macOS 27 displays remains unverified; do not rely on it for a production layout. Hiding never starts automatically at launch. Display changes, sleep, and quitting stop it; Space changes reveal icons. Rehide waits while a popup, mouse press, or Command-drag is detected. **Reveal All** removes the divider entirely.

## Current limitations

No always-hidden tier, automatic physical-icon sorting, per-display layouts, icon image replication below a notch, custom global shortcut editor, spacing/tint/shape customization of the system bar, or self-updater. Realms and groups organize Loki’s shelf, not the physical system menu bar. Hidden/notch-obscured items must first be visible before Loki can click them. Some apps expose incomplete Accessibility labels or no position. Multi-monitor and full-screen behavior needs broader verification.

Loki is an independently developed utility. Its supported capabilities and remaining work are documented in the compatibility ledger.

## Build from source

Requires Apple Silicon, Xcode command-line tools, and Swift. No package downloads are needed.

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

To uninstall: disable launch at login, quit Loki (which removes its divider), then move Loki.app to Trash. Optionally remove the preferences folder and the Loki Accessibility entry in System Settings. Other apps and their data are not removed.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Code and vector artwork are under [MIT](LICENSE). The folded-rune design was developed with AI-assisted concept exploration and recreated as vector paths; no third-party logo artwork is included. No trademark clearance is implied.
