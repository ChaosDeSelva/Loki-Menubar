#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$LOKI_ROOT/build/module-cache"
swiftc -swift-version 5 -module-cache-path "$LOKI_ROOT/build/module-cache" \
  "$LOKI_ROOT/native/ShelfEngine.swift" "$LOKI_ROOT/native/MenuGeometry.swift" "$LOKI_ROOT/native/MenuLabel.swift" "$LOKI_ROOT/tests/TestMain.swift" -o "$LOKI_ROOT/build/loki-tests"
"$LOKI_ROOT/build/loki-tests"
