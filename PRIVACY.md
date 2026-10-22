# Privacy

Loki performs its core work locally. It has no telemetry endpoint, account, web service, analytics SDK, screenshot capture, or clipboard collection.

Accessibility is used to discover menu-extra labels, identifiers, geometry, and owners. Selecting an item sends a mouse click at its current reported position. App shortcuts inspect running applications and activate the chosen one. Data from ordinary application windows and document contents is not intentionally traversed by discovery.

The divider uses on-screen window **geometry and levels**, without reading titles or capturing pixels, to defer rehide while menus are open. Pointer position, mouse-button state, and Command modifier state are checked while divider management is enabled; key contents are not recorded. No input history is saved.

Preferences contain identifiers of pinned/ordered/grouped items, realm names, and settings. Identifiers may reveal which apps you use. Do not publish your personal preferences file. There is no automatic diagnostic upload.

Check for Updates opens the public GitHub releases page in your browser. Downloading the app or visiting the website contacts GitHub; GitHub’s own privacy policy applies. The app does not automatically fetch or install releases.

The public distribution signature identifies its publisher, Reality Software Entertainment LLC, and Apple developer team. A signing identity is public certificate metadata, not a private signing key. No signing keys, passwords, provisioning credentials, or user preference files belong in this repository.
