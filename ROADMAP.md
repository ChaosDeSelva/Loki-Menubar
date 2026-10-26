# Loki-Menubar roadmap

Loki is an early preview. These are planned improvements, not shipped capabilities.

## First: dependable menu access

- Verify on macOS 14 to 26 hardware that Loki’s Command-drags move other apps’ icons and that widening the divider pushes them off-screen. Verify the alpha 6 allowlist end to end on macOS 27, including app launch and quit. Then verify reveal, hover reveal, and rehide on both, on notched displays and multiple monitors. Test open menus, full screen, Spaces, sleep, display reconnects, and app restarts. Keep Reveal All reachable in every state.
- Watch each macOS 27 update for changes to the undocumented allowlist, and adopt a public interface if Apple provides one.
- Improve overflow access for items behind the notch or offscreen. Never activate an unverified coordinate or the application menu in place of a status item.
- Preserve item identity when a utility changes its title or restarts; avoid duplicate system entries and stale assignments.

## Then: useful organization

- Configurable global shortcuts with conflict feedback and keyboard access to groups.
- An optional always-hidden section with an explicit recovery action.
- More user-created realms, per-display layouts, and opt-in profile switching for simple work contexts.
- Local profile export and import with validation, preview, and backup before replacement.
- Group ordering and optional symbols, keeping names and the default shelf simple.

## Release quality

- Measure idle CPU, memory, discovery latency, and long-running stability.
- Expand keyboard, VoiceOver, reduced-motion, and high-contrast checks.
- Validate updates and recovery before adding an in-app installer.

Cloud accounts, clipboard history, and unrelated widgets are outside the current scope. Core menu access and recovery come first.
