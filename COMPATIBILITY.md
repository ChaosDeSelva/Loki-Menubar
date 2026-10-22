# Compatibility and release coverage

This is a preview release. “Implemented” describes code, not proof across all macOS versions. Compatibility coverage is limited to the checks documented below.

## Release checks

Checked on Apple Silicon / macOS 27.0.1:

- Signed build compiles; 35 search, ordering, geometry, grouping, and persistence regression checks pass.
- The menu-extra scan yields one Clock and no Apple-menu entries in the observed setup (previous prototype incorrectly produced dozens of duplicates).
- Escape closes the shelf, verified through the app’s independent `--status` response. The close control also removes Loki’s visible window.
- Selecting Control Center opens a Control Center panel and leaves Loki’s shelf closed. A subsequent automation inspection timed out; this is not a claim of broad third-party menu compatibility.
- Divider setup, tuck, status, and reveal-all commands run. **Actual rendered hiding/hover behavior is not fully verified on macOS 27**; automation screenshots of the composited menu bar were inconclusive.
- A preexisting orphaned menu was traced to its owning UI process and cleared. That recovery does not establish a root cause or prove recurrence impossible.

No notched-MacBook, Intel, older-macOS, sleep/wake soak, or long-running multi-display qualification has been completed.

## Feature ledger

| Capability | Loki status |
| --- | --- |
| Searchable list / keyboard navigation / favorites | Implemented |
| Menu-only launch and dropdown | Implemented |
| Physical icon hiding | Divider compatibility preview; manual setup; visual validation pending |
| Hover reveal / delay / reveal all | Implemented in divider controller; full visual validation pending |
| Physical icon arrangement | macOS Command-drag only |
| Always-hidden section | Not implemented |
| Replica icon bar below a notch | Not implemented; accessible text shelf instead |
| Groups and profiles | Shelf-only groups; independent favorites/order in three realms |
| Per-display automatic profiles | Not implemented |
| Customizable shortcuts / individual item hotkeys | Not implemented; fixed summon shortcut |
| System-bar appearance, shape, spacing | Not implemented |
| Updates | Manual releases link; no self-updater |
| CLI / diagnostics | Local reveal, shelf, settings, status and count-only diagnostics |
| Export/import, localization, sync | Not implemented |

## Reliability priorities

| Area | Current approach and remaining work |
| --- | --- |
| Menu tracking | No remote AXPress or private menu-window mutation. Rehide waits on visible popup metadata. More third-party testing is required. |
| Discovery | Extras-only traversal, system identity deduplication, and bounds validation. Dynamic labels need stronger identity handling. |
| Launch behavior | Accessory app, quiet launch, and an explicitly opened full window. |
| Privacy | No screenshots or screen-recording permission; menu access uses Accessibility. |
| Display changes | Bounded shelf and conservative reveal/stop on layout changes. Broader display coverage is pending. |
| Item persistence | Saved shelf identifiers survive temporary absence. macOS controls physical icon placement. |
| Organization | Shelf groups and realms are implemented. Physical per-display profiles remain absent. |
| Automation | A small local CLI without a network listener. |
| Updates | Manual browser-based release lookup, without a modal updater. |
| Performance | Bounded background discovery and a timer only during divider management. Long-duration profiling is pending. |

System privacy indicators remain owned by macOS. Wallpaper overlays, widgets, animated icons, and cloud accounts are outside the focused release scope.

## Before a stable 1.0

Prove hiding/reveal/recovery on supported OS and display combinations; support inaccessible or notch-obscured items safely; test menu tracking across representative utilities; stabilize identifiers across label changes; qualify login, sleep and display reconfiguration. Only then expand the advertised compatibility range. Appearance and extra integrations come after reliability.

## Alpha 2 validation

Custom group lifecycle, migration, invalid names, offline assignments, realm isolation, and persistence are covered by the 35-check suite. The signed app builds and responds to its status command. Interactive group-editor verification was blocked by a timeout in the UI automation service; this release remains an alpha.
