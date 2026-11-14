#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  -framework AppKit -framework SwiftUI -framework WebKit \
  "$LOKI_ROOT/native/LauncherCore.swift" "$LOKI_ROOT/native/LocalProcessRunner.swift" "$LOKI_ROOT/native/QuickChat.swift" \
  "$LOKI_ROOT/native/AddOnCore.swift" "$LOKI_ROOT/native/AddOnManager.swift" "$LOKI_ROOT/native/AddOnViews.swift" \
  "$LOKI_ROOT/tests/AddOnWebTests.swift" -o "$LOKI_ROOT/build/loki-addon-web-tests"
(cd "$LOKI_ROOT" && "$LOKI_ROOT/build/loki-addon-web-tests")
