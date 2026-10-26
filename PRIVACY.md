# Privacy

Loki performs its core work locally. It has no telemetry endpoint, account, web service, analytics SDK, screenshot capture, or clipboard collection.

Accessibility is used to discover menu-extra labels, identifiers, geometry, and owners. Selecting an item sends a mouse click at its current reported position. On macOS 14 to 26, when you click Apply in Menu bar, Loki posts Command-drag mouse events to move the icons you chose across its divider, re-reads their positions through Accessibility, and returns the pointer to where it was. On macOS 27 Loki posts no drag events for hiding. Event posting relies on the Accessibility permission; Screen Recording is not requested. App shortcuts inspect running applications and activate the chosen one. Data from ordinary application windows and document contents is not intentionally traversed by discovery.

The hiding controller uses on-screen window **geometry and levels**, without reading titles or capturing pixels, to defer rehide while menus are open. Pointer position, mouse-button state, and Command modifier state are checked only while revealed icons are waiting to rehide or hover reveal is on; key contents are not recorded. No input history is saved.

Preferences contain identifiers of pinned/ordered/grouped items, realm names, menu-bar icon identifiers chosen for hiding, and settings. Identifiers may reveal which apps you use. Do not publish your personal preferences file. There is no automatic diagnostic upload.

Updates use Sparkle. Manual checks contact the public GitHub Pages appcast; downloads contact GitHub Releases. Automatic checks are off by default and can be enabled in Settings. Sparkle validates signed archives before extraction and handles installation and relaunch. No realm names, shelf contents, or application inventory are sent; system profiling is disabled. GitHub receives ordinary network request metadata such as IP address. Installation requires user action unless the user explicitly enables an automatic-update option in Sparkle.

The public distribution signature identifies its publisher, Reality Software Entertainment LLC, and Apple developer team. A signing identity is public certificate metadata, not a private signing key. No signing keys, passwords, provisioning credentials, or user preference files belong in this repository.

On macOS 14 to 26, icon hiding uses only public macOS interfaces: an ordinary status item as the divider, and Accessibility to locate and move icons. On macOS 27 it uses one undocumented interface, because no public one can hide icons there: Apple’s MenuBarClientCore allowlist, looked up while Loki runs and never linked or bundled. Loki passes it the bundle identifiers of running apps that should stay visible; nothing leaves your Mac. Loki rewrites no system preference files. Neither the divider’s width nor the allowlist is saved, so quitting Loki shows every icon. On macOS 14 to 26, macOS itself remembers where icons were moved.
