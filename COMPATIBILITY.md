# Compatibility and release coverage

This is a preview release. “Implemented” describes code, not proof across all macOS versions. Compatibility coverage is limited to the checks documented below.

## Release checks

Checked on Apple Silicon / macOS 27.0.1:

- Signed ad-hoc build compiles; the search, ordering, geometry, grouping, persistence, and hidden-section planning regression checks pass.
- The menu-extra scan yields one Clock and no Apple-menu entries in the observed setup (previous prototype incorrectly produced dozens of duplicates).
- Escape closes the shelf, verified through the app’s independent `--status` response. The close control also removes Loki’s visible window.
- Selecting Control Center opens a Control Center panel and leaves Loki’s shelf closed. A subsequent automation inspection timed out; this is not a claim of broad third-party menu compatibility.
- **Menu-bar measurements on macOS 27.0.1, one Mac.** A synthesized Command-drag moved another app’s icon one slot and back to its exact original x. Accessibility reported positions for third-party and system menu extras. Widening a status item pushed icons left only while the item fit: up to about 1,660 points on a 3,360-point display with app menus ending at x=509. At that widest fitting width the icon was still on screen. Any wider, macOS dropped the widened item entirely and the icons returned. Conclusion: on macOS 27 a normal app cannot push icons off-screen, so public-API hiding is not possible there, and Loki uses the undocumented allowlist instead.
- A preexisting orphaned menu was traced to its owning UI process and cleared. That recovery does not establish a root cause or prove recurrence impossible.

No notched-MacBook, Intel, older-macOS, sleep/wake, or multi-display qualification has been completed.

## Feature ledger

| Capability | Loki status |
| --- | --- |
| Searchable list / keyboard navigation / favorites | Implemented |
| Menu-only launch and dropdown | Implemented |
| Physical icon hiding | macOS 14 to 26: per icon, a public divider status item widened to push icons left of it off-screen; implemented, not yet verified on macOS 14 to 26 hardware. macOS 27: per app, Apple’s undocumented MenuBarClientCore allowlist, resolved at runtime and off if absent or changed; Apple system controls and Loki always stay visible. Alpha 5 hide and return observed by a user; alpha 6 end to end pending |
| Hover reveal / delay / reveal all | Both mechanisms: Option-click, menus, and CLI toggle; optional hover on the menu-bar band (off by default); auto-rehide after 3 s by default; reveal all pauses rehiding. ‹ chevron on the divider (macOS 14 to 26 only). Implemented, pending hardware verification |
| Physical icon arrangement | macOS 14 to 26 only: Loki Command-drags chosen icons across its divider and verifies each move through Accessibility. Clock and Control Center cannot move. Implemented, not yet verified on macOS 14 to 26 hardware. On macOS 27 the drag itself was measured to work, but Loki does not use it, since the divider cannot hide there |
| Always-hidden section | Not implemented |
| Replica icon bar below a notch | Not implemented; accessible text shelf instead |
| Groups and profiles | Shelf groups; independent favorites, order, and hidden-icon choices in three realms |
| Per-display automatic profiles | Not implemented |
| Customizable shortcuts / individual item hotkeys | Not implemented; fixed summon shortcut |
| System-bar appearance, shape, spacing | Not implemented |
| Updates | Sparkle signed download, install, and relaunch; automatic checks opt-in |
| CLI / diagnostics | Local reveal-all, hidden-icon toggle, shelf, settings, JSON status, and count-only diagnostics |
| Export/import, localization, sync | Not implemented |

## Reliability priorities

| Area | Current approach and remaining work |
| --- | --- |
| Menu tracking | No remote AXPress or private menu-window mutation. Rehide waits on visible popup metadata. More third-party testing is required. |
| Discovery | Extras-only traversal, system identity deduplication, and bounds validation. Third-party titles no longer define identity; unnamed items use per-owner traversal slots. Reordering multiple unnamed extras remains ambiguous. |
| Launch behavior | Accessory app, quiet launch, and an explicitly opened full window. |
| Privacy | No screenshots or Screen Recording permission. macOS 14 to 26 uses public interfaces only; macOS 27 uses one undocumented interface, because no public one can hide icons there. Menu access and icon moves use Accessibility. |
| Display changes | Bounded shelf. On macOS 14 to 26 a display change reveals hidden icons; if the divider is no longer left of the rune, rehiding pauses. Display coverage is pending hardware verification. |
| Item persistence | Saved shelf identifiers survive temporary absence. macOS saves icon positions. Neither the divider width nor the allowlist is saved, so a quit or crash shows every icon. On macOS 27 the allowlist is refreshed when apps launch or quit, so new apps stay visible. |
| Organization | Shelf groups and realms are implemented. Physical per-display profiles remain absent. |
| Automation | A small local CLI without a network listener. |
| Updates | Sparkle with pinned dependency, archive signature validation, and optional automatic checks. |
| Performance | Bounded background discovery and a timer only while revealed icons await rehide or hover reveal is on. Long-duration profiling is pending. |

System privacy indicators remain owned by macOS. Wallpaper overlays, widgets, animated icons, and cloud accounts are outside the focused release scope.

## Before a stable 1.0

Prove arrangement, hiding, reveal, and recovery on supported OS and display combinations; support inaccessible or notch-obscured items safely; test menu tracking across representative utilities; stabilize identifiers across label changes; qualify login, sleep and display reconfiguration. Only then expand the advertised compatibility range. Appearance and extra integrations come after reliability.

## Alpha 2 validation

Custom group lifecycle, migration, invalid names, offline assignments, realm isolation, and persistence are covered by the 35-check suite. The signed app builds and responds to its status command. Interactive group-editor verification was blocked by a timeout in the UI automation service; this release remains an alpha.

## Alpha 3 validation

The layout was rendered from SwiftUI and inspected for form alignment, compact header/footer, and toolbar spacing. The Superpowers independent review led to canonical system-item IDs with legacy preference migration, nested-popover Escape handling, and suppression of stale undo actions. macOS 27 hiding was unavailable in alpha 3.

## Alpha 4 validation

The 50-check suite includes changing-label favorites and groups, distinct unnamed slots, and conservative legacy-ID migration. A real duplicate-launch check exited successfully while the existing process remained running. Shutdown tolerates an uninitialized model, keyboard selection scrolls into view, and the personality setting changes shelf copy. Legacy title-based preferences migrate when that title is observed again; already-changed titles cannot be safely matched automatically. Full interactive updater installation/relaunch and broad third-party menu qualification remain pending.

## Alpha 5 validation

The runtime bridge, still used on macOS 27 in alpha 6, was built from local Apple runtime method metadata and SDK symbol declarations. A bounded live probe received a successful activation callback. On October 22, 2026, a user-observed repeat confirmed the test icon disappeared during hiding and returned on reveal, with other icons remaining visible. This confirms the tested hide/reveal cycle, not every app or display configuration. The UI automation service timed out, and a standalone read-only Accessibility probe lacked permission. Forced-process-death recovery remains unverified; normal release and asynchronous cancellation are covered separately. Tests with runtime stand-ins cover cancellation, late completion, replacement requests, errors, empty allowlists, and owner destruction without affecting the real menu bar. SwiftPM manifest validation and the signed app build pass. The optional SwiftPM build was stopped while its Sparkle binary dependency download stalled; the release-script build is verified.

## Alpha 6 validation

Hiding has two backends behind one checklist. macOS 14 to 26 uses a public divider: Loki Command-drags chosen icons left of it and widens it. macOS 27 keeps the alpha 5 MenuBarClientCore allowlist, because measurement on macOS 27.0.1 showed a widened status item cannot push icons off-screen there (see Release checks). The manual divider setup was removed. On macOS 27.0.1 the regression suite passes (142 checks plus 13 bridge lifecycle checks) and covers divider widths, ordering validity, move planning, drop points, unmovable system items, rehide conditions, coordinate flipping, app ownership of menu extras, and the allowlist’s always-visible Apple and Loki entries. The app builds with an ad-hoc signature and with Developer ID.

Verified on macOS 27.0.1 by the owner watching the menu bar (October 25, 2026): with one app chosen, only that app's icon disappeared and every other icon, including Loki's, stayed; Reveal All and quitting brought it back; Apple's allowlist honored separate app and system lists. Three defects were found that way and fixed: a build-folder copy of Loki hid its own icon (macOS matches only apps it tracks, so Loki now refuses to hide outside an Applications folder); an app opened while icons were hidden stayed hidden (the allowlist now includes every installed app, not only running ones); and repeated rehide requests cancelled each other. The allowlist now replaces itself only after macOS confirms the new one, allows the full system item range, and steps aside while a microphone or camera is in use. The bridge suite covers the replacement order (13 checks).

Not yet verified on hardware: everything on macOS 14 to 26, including Command-drag arrangement and icons going off-screen when the divider widens. Pending on macOS 27 after the fixes above: an app opened while icons are hidden, Option-click reveal, the microphone and camera pause, and the 5-second confirmation fallback. Also pending on both: hover reveal and auto-rehide, multiple displays, notched displays, and sleep/wake. Alpha 5 per-app choices are ignored and must be chosen again. This release remains an alpha and is not qualified for managed or enterprise deployment.
