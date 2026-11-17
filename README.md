# Loki-Menubar

A little order. A little mischief. An original Swift/AppKit menu-bar utility for macOS, with a searchable shelf, favorites, and Nordic-inspired profiles.

[Download & installation](https://chaosdeselva.github.io/Loki-Menubar/) · [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases) · [Compatibility](COMPATIBILITY.md)

## Release status

**0.1.0-alpha.8 is an early preview,** published as a notarized pre-release. Apple Silicon; macOS 14 or later. Alpha 8 keeps newly launched icons visible unless selected for hiding and improves menu-item targeting. Loki hides icons two ways, depending on the macOS version: per icon behind a public divider on macOS 14 to 26, and per app through an undocumented Apple interface on macOS 27. On macOS 27.0.1 the owner confirmed that hiding one app left every other icon visible; the rest of the matrix is pending, see [Hide icons](#hide-icons). Earlier macOS versions, notched MacBooks, and multiple displays are not yet verified. See the explicit feature gaps below before installing.

## What is included

- A menu-bar dropdown, separate from the explicitly opened settings window; no Dock icon or launch-time window.
- Search, arrow-key navigation, Return to open, favorites, and drag ordering within Loki’s shelf.
- Separate sources for real menu extras and running-application shortcuts.
- Three renameable realms with independent favorites, order, custom groups, and hidden-icon choices. Open Groups to create, rename, or remove categories such as Development, Meetings, or Home. Right-click a row to assign its group. Renaming retains assignments; removing a group returns items to Ungrouped.
- Menu discovery restricted to Accessibility menu-extra trees, excluding the Apple/File/Edit trees.
- Opening an item closes Loki first, resolves its accessible position, and posts a normal mouse click off the UI thread. Stale/unpositioned items fail with an explanation.
- An explicit close button, Escape, outside-click dismissal, and Control-Option-L to summon/toggle the shelf.
- Reloadable add-ons with script commands, native forms, and custom local HTML interfaces. Install or update packages without rebuilding Loki.
- Optional **Loki Launch** add-on: installed-app and command search, a configurable global shortcut, and Quick Chat using Claude Code or Codex subscription sign-ins.
- Icon hiding with one checklist: per icon behind a divider on macOS 14 to 26, per app on macOS 27. Option-click reveal, optional hover reveal, delayed rehide, and reveal-all recovery on both.
- Launch at login, three accent colors, local preferences, and preservation of corrupted settings files.
- CLI commands for the shelf, settings, hidden icons, reveal-all, status, and privacy-limited diagnostics.
- No analytics, Loki account, or screen capture. Optional chat uses your provider account. macOS 14 to 26 uses public interfaces only; macOS 27 uses one undocumented interface, because no public one can hide icons there. Sparkle is the bundled update dependency; automatic checks are opt-in.

## Install

Download the Apple Silicon DMG from [Releases](https://github.com/ChaosDeSelva/Loki-Menubar/releases), open it, and drag **Loki.app** into **Applications**. Launch Loki, then click its rune icon in the menu bar. Use the expand button to open the main window.

App shortcuts do not need Accessibility. Menu extras and the hidden-icons checklist do, and on macOS 14 to 26 so does moving icons: in **Menu items** or **Menu bar**, choose **Allow Accessibility** and enable the installed app in System Settings. A previous development build may have a different bundle identifier and permission entry; the public release uses `io.github.ChaosDeSelva.Loki`.

## Loki Launch (optional add-on)

In a source build, open **Add-ons → Enable Loki Launch** (also available in Settings). It is off by default. Press **Shift-Command-Space** to toggle a floating launcher on the display containing your pointer. Click the shortcut to choose its modifiers and key. Conflicts detected through macOS shortcut settings or exclusive hotkey registration are rejected, preserving your previous shortcut. The existing **Control-Option-L** shelf shortcut is separate.

Search installed apps in `/Applications`, `/System/Applications`, macOS's CoreServices and Cryptex Applications folders, and `~/Applications`, including apps inside subfolders. Search also finds Loki commands such as Open Shelf and Reveal All. Use arrow keys and Return, or click a result. Escape and outside clicks dismiss the panel. Search stays local; the app index refreshes when you open the launcher after a minute.

Press **Tab** to switch between Search and Quick Chat; focus follows to the search box or chat composer, and each keeps its text. Shift-Tab retains ordinary focus navigation. Add-on forms keep their normal Tab navigation. You can also choose **Quick Chat** (Command-2; Command-1 returns to search) for questions and follow-ups. Choose Claude or Codex, type a message, and press Return or Send. Replies can be copied, stopped, or cleared with **New Chat** (Command-N). Switching providers starts a fresh chat. Choose **History** to search and reopen earlier conversations, including chats from either provider. Reopening a chat selects its original provider. **New Chat** starts another conversation; previous chats remain in History. Use the trash button and confirm Delete to remove a saved chat. Conversations are stored locally on this Mac and survive quitting Loki. Drafts are not saved, and there is no cloud sync.

Install a current official [Claude Code](https://code.claude.com/docs/en/quickstart) or [Codex CLI](https://developers.openai.com/codex/cli/) and sign in once in Terminal:

```sh
claude auth login
# or
codex login
```

Choose the subscription sign-in, not an API key. Loki checks the client's authentication method before sending and rejects API-key sign-ins. It discovers clients in `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`; **Choose client…** supports other installation paths. It uses the client's default model and your plan's limits. The clients handle their own credentials; Loki never reads or copies tokens. Recent CLI versions are required for isolated settings and nonpersistent sessions; update the client if it reports an unsupported option.

Quick Chat runs in a temporary empty directory. Claude tools and MCP servers are disabled. Codex runs read-only, with shell tools, connected apps, hooks, and user-configured MCP servers disabled. No application inventory or menu-bar contents are added to your messages. Only a submitted chat uses the provider; turning on search does not start an AI client. Provider retention and usage policies still apply; see [Privacy](PRIVACY.md).

This implementation uses native AppKit/SwiftUI and Carbon hotkeys. It contains no Raycast code, SDK, assets, or services. The published alpha listed above predates this source feature.

## Reloadable add-ons

Open **Add-ons → Install folder…** or **Add examples**, then enable a package. Its commands appear in Loki Launch. Edit or replace its folder to update it; Loki reloads automatically and asks you to enable changed code again. Scripts run with your account’s file and network access, so enable only trusted packages. The [add-on authoring guide](addons/README.md) covers the manifest, forms, script input/output, local data, and custom HTML bridge. Add-on updates do not replace the host app or change its Accessibility identity.

## Hide icons

1. Open Loki’s full window and select **Menu bar**. Loki lists your menu-bar icons through Accessibility.
2. Switch on the icons you want out of sight. Choices are saved in the current realm.
3. Click **Apply**.

What happens next depends on the macOS version.

**macOS 14 to 26: per icon.** Loki delivers Command-drag events directly to the status-window host, using an undocumented event-window field to address icons outside the visible menu bar. It does not synthesize a global mouse-move stream or warp the cursor. After each attempt, Loki collapses its divider and re-reads Accessibility positions to check which icons actually crossed it; dispatching events alone is not success. Unchosen icons belong to the right of the divider. If an unchosen icon cannot be recovered, hiding pauses rather than deliberately concealing it. A crowded or notched screen can still prevent that icon from being drawn while revealed. Clock and Control Center cannot be moved. The revised offscreen delivery path requires hardware verification with a signed build; automated event-construction tests do not establish that macOS accepts the drag.

**macOS 27: per app, one undocumented interface.** Measured on macOS 27.0.1 on one Mac: synthesized Command-drags do move other apps’ icons, and Accessibility reports their positions, but widening a status item pushes icons left only while the item fits. On a 3,360-point display with app menus ending at x=509, that was up to about 1,660 points, and at that width the icon was still on screen. Any wider, macOS drops the widened item and the icons return. A normal app therefore cannot push icons off-screen on macOS 27, so the divider cannot hide anything there. Instead Loki uses Apple’s undocumented MenuBarClientCore allowlist. It is looked up while Loki runs; nothing is linked or bundled, and hiding turns itself off if the interface is missing or has changed. The allowlist works per app: choosing any icon of an app hides all of that app’s icons. Apple’s system controls and Loki itself always stay visible and are not offered. Hiding itself does not need Accessibility. Apps launched while icons are hidden stay visible, because Loki refreshes the allowlist when an app launches or quits instead of revealing everything. On macOS 27.0.1 the owner watched alpha 6 hide one app while every other icon, Loki included, stayed visible. The allowlist also includes every installed app, so apps opened while icons are hidden stay visible, and Loki steps aside while a microphone or camera is in use.

To get icons back: Option-click the rune, right-click it and choose **Show Hidden Icons**, choose **Show or Hide Hidden Icons** from Loki’s app menu, or run `--toggle-hidden`. Hover reveal is available in **Menu bar** and is off by default; it reacts only to the menu-bar band itself. On macOS 14 to 26, click the ‹ chevron on the divider to hide them again. By default they rehide 3 seconds after the pointer leaves the menu bar, and rehiding waits while a menu is open, a mouse button is down, or Command is held. On macOS 27, rehiding asks macOS again; if macOS does not confirm within 5 seconds, Loki shows everything. Hidden icons stay on Loki’s shelf; opening one reveals them first. Alpha 5 per-app choices are not carried over; choose icons again after updating.

**Recovery.** Neither mechanism is saved: the divider’s width and the allowlist both end with Loki, so quitting Loki, or a crash, shows every icon (by design; recovery after a forced crash has not been tested). **Reveal All Menu Bar Items** shows everything and pauses rehiding until you hide again. On macOS 14 to 26 a display change reveals the section. At launch, if icons were chosen, Loki hides them again after about a second.

## Current limitations

No always-hidden tier, per-display layouts, icon image replication below a notch, custom shelf shortcut editor, spacing/tint/shape customization of the system bar, or background physical-layout automation. Groups organize the shelf. Switching to a realm with different hidden-icon choices applies them again (on macOS 14 to 26, by moving icons). On macOS 27 hiding is per app, and Apple’s own menu-bar icons cannot be hidden. While icons are hidden on macOS 27, macOS itself may stop the clock from opening Notification Center and may hide Now Playing; Loki shows every icon while a microphone or camera is in use so the recording indicators stay intact. Run Loki from your Applications folder: on macOS 27 a copy elsewhere is not matched by macOS and would hide its own icon, so Loki refuses to hide from there. Notch-obscured items must first be visible before Loki can click them. Some apps expose incomplete Accessibility labels or no position. Multi-display, notch, sleep/wake, and full-screen behavior of both hiding mechanisms, and all macOS 14 to 26 hiding, are implemented, not yet verified on hardware.

Loki is an independently developed utility. Its supported capabilities and remaining work are documented in the compatibility ledger.

## Build from source

Requires Apple Silicon, Xcode command-line tools, and Swift. The first build downloads the checksum-pinned Sparkle framework from its official release.

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Loki.app
```

On a Mac with an active desktop session, `bash scripts/test-shortcuts.sh` also checks live shortcut registration, conflict handling, remapping, and cleanup with temporary test hotkeys. `bash scripts/test-addons-ui.sh` checks the live WebKit bridge using a temporary example package.

The build defaults to an ad-hoc local signature. For a Developer ID build:

```sh
LOKI_SIGN_IDENTITY='Developer ID Application: Your Organization (TEAMID)' bash scripts/build.sh
```

Releases are moving to Developer ID signing and notarization; see [docs/RELEASING.md](docs/RELEASING.md) for the release process. Signing credentials are external to the repository. `LOKI_BUNDLE_ID` can override the bundle identifier for local development. Do not publish private certificates, keychain profiles, local preferences, or raw diagnostic logs.

## Command line

With the installed app running:

```sh
/Applications/Loki.app/Contents/MacOS/Loki --shelf
/Applications/Loki.app/Contents/MacOS/Loki --settings
/Applications/Loki.app/Contents/MacOS/Loki --launcher
/Applications/Loki.app/Contents/MacOS/Loki --quick-chat
/Applications/Loki.app/Contents/MacOS/Loki --toggle-hidden
/Applications/Loki.app/Contents/MacOS/Loki --reveal-all
/Applications/Loki.app/Contents/MacOS/Loki --status
```

`--status` prints JSON with `concealed`, `arranging`, `hiddenCount`, `mode`, `backend` (`divider`, `allowlist`, or `unavailable`), `paused`, `orderingValid`, `message`, `shelfOpen`, `launcherEnabled`, `launcherOpen`, `launcherShortcutRegistered`, `launcherShortcut`, `launcherShortcutError`, `launcherTab`, `selectedRealm`, and `accessibility`. `--launcher` toggles Loki Launch, or opens its add-on settings if disabled. `--quick-chat` opens the chat tab. `--diagnose` runs a standalone count-only discovery report. It reports `hidingBackend` (`divider`, `allowlist`, or `unavailable`) and `privateFrameworks`, which is `true` only when the macOS 27 allowlist is in use. It contains no menu titles, file names, app list, or preferences. The CLI uses local notifications, not a network listener.

## Data and uninstall

Preferences live in `~/Library/Application Support/Loki/preferences.json`. They contain realm names, saved item identifiers, hidden-icon choices, group assignments, and preferences. The optional launcher's enablement, shortcut, provider, and executable paths live alongside them in `launcher.json`. Quick Chat conversations live in `Chat History/history.json`, in a directory restricted to your Mac account. Reloadable packages live in `Add-ons/`, their approval fingerprints in `addons.json`, and their persistent data in `Add-on Data/`. There is no cloud sync. See [PRIVACY.md](PRIVACY.md).

To uninstall: disable launch at login, quit Loki (which shows every icon), then move Loki.app to Trash. Optionally remove the preferences folder and the Loki Accessibility entry in System Settings. Other apps and their data are not removed.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Code and vector artwork are under [MIT](LICENSE). The folded-rune design was developed with AI-assisted concept exploration and recreated as vector paths; no third-party logo artwork is included. No trademark clearance is implied.

See [the roadmap](ROADMAP.md) for prioritized improvements and release-quality criteria.

### Alpha 3 fixes

Compact popup controls, consistent form heights, group deletion confirmation and session undo, improved system-menu labels, and signed in-app updates. Automatic update checks are opt-in in Settings.

### Alpha 6 changes

Hiding is chosen per icon from one checklist. On macOS 14 to 26, Loki moves chosen icons behind its public divider itself, verifies each move, and widens the divider; the manual Command-drag setup is gone. On macOS 27, where measurement showed widening cannot push icons off-screen, Loki keeps the undocumented allowlist, now refreshed when apps launch or quit so new apps stay visible, and confirmed within 5 seconds or everything is shown. The version shown in the app is read from its Info.plist. Releases move to Developer ID signing and notarization. Unit, bridge, and controller tests pass, and the release is Developer ID signed and notarized. Hiding on macOS 14 to 26 is not yet verified on hardware, and on macOS 27 only single-app hiding and Reveal All are verified on hardware; see [COMPATIBILITY.md](COMPATIBILITY.md).
