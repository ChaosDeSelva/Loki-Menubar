#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  "$LOKI_ROOT/native/ShelfEngine.swift" "$LOKI_ROOT/native/MenuGeometry.swift" "$LOKI_ROOT/native/MenuLabel.swift" "$LOKI_ROOT/native/MenuBarSections.swift" "$LOKI_ROOT/native/ManagedPolicy.swift" "$LOKI_ROOT/tests/TestMain.swift" -o "$LOKI_ROOT/build/loki-tests"
"$LOKI_ROOT/build/loki-tests"
clang -fobjc-arc -I "$LOKI_ROOT/nativeBridge/include" -framework Foundation "$LOKI_ROOT/nativeBridge/LOKMenuBarBridge.m" "$LOKI_ROOT/tests/VisibilityBridgeTests.m" -o "$LOKI_ROOT/build/loki-bridge-tests"
"$LOKI_ROOT/build/loki-bridge-tests"
# Controller bookkeeping against a fake allowlist; never touches the real menu bar.
clang -fobjc-arc -I "$LOKI_ROOT/nativeBridge/include" -c "$LOKI_ROOT/nativeBridge/LOKMenuBarBridge.m" -o "$LOKI_ROOT/build/controller-bridge.o"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  -import-objc-header "$LOKI_ROOT/nativeBridge/include/LOKMenuBarBridge.h" "$LOKI_ROOT/build/controller-bridge.o" \
  -framework AppKit -framework ApplicationServices -framework CoreAudio -framework CoreMediaIO \
  "$LOKI_ROOT/native/VisibilityController.swift" "$LOKI_ROOT/native/MenuBarSections.swift" "$LOKI_ROOT/native/MenuBarVisibility.swift" \
  "$LOKI_ROOT/native/MenuBarArranger.swift" "$LOKI_ROOT/native/MenuDiscovery.swift" "$LOKI_ROOT/native/CaptureActivity.swift" \
  "$LOKI_ROOT/native/MenuLabel.swift" "$LOKI_ROOT/native/ShelfEngine.swift" "$LOKI_ROOT/native/MenuGeometry.swift" \
  "$LOKI_ROOT/tests/ControllerTests.swift" -o "$LOKI_ROOT/build/loki-controller-tests"
"$LOKI_ROOT/build/loki-controller-tests"
