# Compatibility and release coverage

This is a preview release. “Implemented” describes code, not proof across all macOS versions. Compatibility coverage is limited to the checks documented below.

## Release checks

Checked on Apple Silicon / macOS 27.0.1:

- Signed build compiles; 53 search, ordering, geometry, grouping, persistence, and visibility-plan regression checks plus 9 bridge lifecycle checks pass.
- The menu-extra scan yields one Clock and no Apple-menu entries in the observed setup (previous prototype incorrectly produced dozens of duplicates).
- Escape closes the shelf, verified through the app’s independent `--status` response. The close control also removes Loki’s visible window.
- Selecting Control Center opens a Control Center panel and leaves Loki’s shelf closed. A subsequent automation inspection timed out; this is not a claim of broad third-party menu compatibility.
- **macOS 27 uses an opt-in app allowlist.** The runtime interface and activation callback were checked on macOS 27.0.1. A user-observed test confirmed the test icon disappeared and returned while other icons remained visible. Forced-process-death recovery remains unverified. The older spacer path is limited to macOS 14–26 and still requires hardware qualification.
- A preexisting orphaned menu was traced to its owning UI process and cleared. That recovery does not establish a root cause or prove recurrence impossible.

No notched-MacBook, Intel, older-macOS, sleep/wake soak, or long-running multi-display qualification has been completed.

## Feature ledger

| Capability | Loki status |
| --- | --- |
| Searchable list / keyboard navigation / favorites | Implemented |
| Menu-only launch and dropdown | Implemented |
| Physical icon hiding | App-selection backend on macOS 27; experimental manual divider on macOS 14–26 |
| Hover reveal / delay / reveal all | Implemented for both hiding backends; full visual validation pending |
| Physical icon arrangement | macOS Command-drag only |
| Always-hidden section | Not implemented |
| Replica icon bar below a notch | Not implemented; accessible text shelf instead |
| Groups and profiles | Shelf groups; independent favorites/order and macOS 27 app-hiding choices in three realms |
| Per-display automatic profiles | Not implemented |
| Customizable shortcuts / individual item hotkeys | Not implemented; fixed summon shortcut |
| System-bar appearance, shape, spacing | Not implemented |
| Updates | Sparkle signed download, install, and relaunch; automatic checks opt-in |
| CLI / diagnostics | Local reveal, shelf, settings, status and count-only diagnostics |
| Export/import, localization, sync | Not implemented |

## Reliability priorities

| Area | Current approach and remaining work |
| --- | --- |
| Menu tracking | No remote AXPress or private menu-window mutation. Rehide waits on visible popup metadata. More third-party testing is required. |
| Discovery | Extras-only traversal, system identity deduplication, and bounds validation. Third-party titles no longer define identity; unnamed items use per-owner traversal slots. Reordering multiple unnamed extras remains ambiguous. |
| Launch behavior | Accessory app, quiet launch, and an explicitly opened full window. |
| Privacy | No screenshots or screen-recording permission; menu access uses Accessibility. |
| Display changes | Bounded shelf and conservative reveal/stop on layout changes. Broader display coverage is pending. |
| Item persistence | Saved shelf identifiers survive temporary absence. macOS controls physical icon placement. |
| Organization | Shelf groups and realms are implemented. Physical per-display profiles remain absent. |
| Automation | A small local CLI without a network listener. |
| Updates | Sparkle with pinned dependency, archive signature validation, and optional automatic checks. |
| Performance | Bounded background discovery and a timer only during divider management. Long-duration profiling is pending. |

System privacy indicators remain owned by macOS. Wallpaper overlays, widgets, animated icons, and cloud accounts are outside the focused release scope.

## Before a stable 1.0

Prove hiding/reveal/recovery on supported OS and display combinations; support inaccessible or notch-obscured items safely; test menu tracking across representative utilities; stabilize identifiers across label changes; qualify login, sleep and display reconfiguration. Only then expand the advertised compatibility range. Appearance and extra integrations come after reliability.

## Alpha 2 validation

Custom group lifecycle, migration, invalid names, offline assignments, realm isolation, and persistence are covered by the 35-check suite. The signed app builds and responds to its status command. Interactive group-editor verification was blocked by a timeout in the UI automation service; this release remains an alpha.

## Alpha 3 validation

The layout was rendered from SwiftUI and inspected for form alignment, compact header/footer, and toolbar spacing. The Superpowers independent review led to canonical system-item IDs with legacy preference migration, nested-popover Escape handling, and suppression of stale undo actions. macOS 27 hiding remains explicitly unavailable.

## Alpha 4 validation

The 50-check suite includes changing-label favorites and groups, distinct unnamed slots, and conservative legacy-ID migration. A real duplicate-launch check exited successfully while the existing process remained running. Shutdown tolerates an uninitialized model, keyboard selection scrolls into view, and the personality setting changes shelf copy. Legacy title-based preferences migrate when that title is observed again; already-changed titles cannot be safely matched automatically. Full interactive updater installation/relaunch and broad third-party menu qualification remain pending.

## Alpha 5 validation

The original runtime bridge was built from local Apple runtime method metadata and SDK symbol declarations. A bounded live probe received a successful activation callback. On October 22, 2026, a user-observed repeat confirmed the test icon disappeared during hiding and returned on reveal, with other icons remaining visible. This confirms the tested hide/reveal cycle, not every app or display configuration. The UI automation service timed out, and a standalone read-only Accessibility probe lacked permission. Forced-process-death recovery remains unverified; normal release and asynchronous cancellation are covered separately. Tests with runtime stand-ins cover cancellation, late completion, replacement requests, errors, empty allowlists, and owner destruction without affecting the real menu bar. SwiftPM manifest validation and the signed app build pass. The optional SwiftPM build was stopped while its Sparkle binary dependency download stalled; the release-script build is verified.
