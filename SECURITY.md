# Security

Do not post credentials, private logs, or personal preferences in issues. Use GitHub’s private vulnerability reporting for sensitive reports when available; otherwise open a minimal issue asking for a private contact without disclosing the vulnerability details.

Accessibility permits broad UI control. Loki limits its own discovery to menu-extra trees and user-selected activation. On macOS 14 to 26, Loki posts synthesized Command-drag events only when you click Apply in Menu bar, and only between menu-bar icons and its divider. On macOS 27, hiding instead calls one undocumented Apple interface (MenuBarClientCore), resolved at runtime and disabled automatically if it is absent or has changed; it receives only bundle identifiers of apps to keep visible. Report any path that reaches unrelated document content, or that clicks or drags outside the validated menu-bar bounds.

Release artifacts should be Developer ID signed and notarized, with SHA-256 checksums; [docs/RELEASING.md](docs/RELEASING.md) covers the process. A source build is ad-hoc signed unless the builder supplies a signing identity. Preview releases are not a security or compatibility guarantee.
