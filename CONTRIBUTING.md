# Contributing

Use original implementation work. Do not copy code from differently licensed menu managers into this MIT repository without a separate licensing review.

Build with `bash scripts/build.sh` and run `bash scripts/test.sh`. Keep core ordering/search/persistence logic testable without Accessibility. Add regression coverage for substantive behavior changes.

For UI changes, check launch stays quiet, status-click opens only the shelf, Escape/close/outside click dismiss it, and menu activation does not block the main thread. Exercise busy or terminated owners and denied/revoked permissions. Never enable concealment on launch or silently manipulate system preferences.

For hiding changes, verify reveal-all, quitting, sleep, screen changes, full-screen Spaces, active popup tracking, and multi-display behavior. Record OS/hardware coverage honestly. A state flag changing is not proof that macOS rendered the desired result.

Report issues with macOS version, display arrangement, reproduction steps and expected/actual behavior. Count-only `--diagnose` output is usually sufficient. Redact app names, personal paths and menu contents from screenshots and logs before posting. Never attach credentials or personal preferences.
