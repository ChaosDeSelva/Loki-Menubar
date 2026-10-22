# Privacy

Loki performs its core work locally. It has no telemetry endpoint, account, web service, analytics SDK, screenshot capture, or clipboard collection.

Accessibility is used to discover menu-extra labels, identifiers, geometry, and owners. Selecting an item sends a mouse click at its current reported position. App shortcuts inspect running applications and activate the chosen one. Data from ordinary application windows and document contents is not intentionally traversed by discovery.

The hiding controller uses on-screen window **geometry and levels**, without reading titles or capturing pixels, to defer rehide while menus are open. Pointer position, mouse-button state, and Command modifier state are checked while hiding is enabled; key contents are not recorded. No input history is saved.

Preferences contain identifiers of pinned/ordered/grouped items, realm names, selected apps to hide, and settings. Identifiers may reveal which apps you use. Do not publish your personal preferences file. There is no automatic diagnostic upload.

Updates use Sparkle. Manual checks contact the public GitHub Pages appcast; downloads contact GitHub Releases. Automatic checks are off by default and can be enabled in Settings. Sparkle validates signed archives before extraction and handles installation and relaunch. No realm names, shelf contents, or application inventory are sent; system profiling is disabled. GitHub receives ordinary network request metadata such as IP address. Installation requires user action unless the user explicitly enables an automatic-update option in Sparkle.

The public distribution signature identifies its publisher, Reality Software Entertainment LLC, and Apple developer team. A signing identity is public certificate metadata, not a private signing key. No signing keys, passwords, provisioning credentials, or user preference files belong in this repository.

On macOS 27, opt-in icon hiding loads the system MenuBarClientCore framework and holds a temporary menu-bar visibility assertion. It sends an app allowlist and the runtime’s system-control identifiers to the local macOS menu-bar service. It does not start an exam session or change device security policy. Releasing the assertion requests restoration; no system preference files are rewritten. This undocumented interface can change with macOS updates. Earlier versions use a status-item divider.
