#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  "$LOKI_ROOT/native/ShelfEngine.swift" "$LOKI_ROOT/native/MenuGeometry.swift" "$LOKI_ROOT/native/MenuLabel.swift" "$LOKI_ROOT/tests/TestMain.swift" -o "$LOKI_ROOT/build/loki-tests"
"$LOKI_ROOT/build/loki-tests"
clang -fobjc-arc -I "$LOKI_ROOT/nativeBridge/include" -framework Foundation   "$LOKI_ROOT/nativeBridge/LOKMenuBarBridge.m" "$LOKI_ROOT/tests/VisibilityBridgeTests.m"   -o "$LOKI_ROOT/build/loki-bridge-tests"
"$LOKI_ROOT/build/loki-bridge-tests"
