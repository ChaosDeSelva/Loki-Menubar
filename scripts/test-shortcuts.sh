#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  -framework AppKit -framework SwiftUI -framework Carbon \
  "$LOKI_ROOT/native/LauncherCore.swift" "$LOKI_ROOT/native/LocalProcessRunner.swift" "$LOKI_ROOT/native/QuickChat.swift" \
  "$LOKI_ROOT/native/AddOnCore.swift" "$LOKI_ROOT/native/AddOnManager.swift" "$LOKI_ROOT/native/Launcher.swift" "$LOKI_ROOT/native/LauncherShortcut.swift" \
  "$LOKI_ROOT/tests/LauncherShortcutTests.swift" -o "$LOKI_ROOT/build/loki-shortcut-tests"
"$LOKI_ROOT/build/loki-shortcut-tests"
