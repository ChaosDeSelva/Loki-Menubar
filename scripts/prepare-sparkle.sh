#!/bin/bash
set -euo pipefail
LOKI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOKI_VENDOR="$LOKI_ROOT/build/vendor"
LOKI_ARCHIVE="$LOKI_VENDOR/Sparkle-2.10.0.tar.xz"
mkdir -p "$LOKI_VENDOR"
if [[ ! -f "$LOKI_ARCHIVE" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$LOKI_ARCHIVE"
fi
printf '%s  %s\n' 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c' "$LOKI_ARCHIVE" | shasum -a 256 -c -
mkdir -p "$LOKI_VENDOR/Sparkle"
tar -xf "$LOKI_ARCHIVE" -C "$LOKI_VENDOR/Sparkle"
