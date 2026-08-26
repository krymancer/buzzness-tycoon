#!/usr/bin/env bash
# Build both targets in ReleaseFast and stage both binaries into a single
# depot content folder (steam/content/all/). The app ships one "All OSes"
# depot (4980571) containing both executables; per-OS launch options in the
# Steamworks dashboard pick the right one. Run before uploading with steamcmd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DEST=steam/content/all
mkdir -p "$DEST"

echo "==> Building Linux (native) ..."
zig build -Doptimize=ReleaseFast
cp -f zig-out/bin/buzzness-tycoon "$DEST/buzzness-tycoon"
chmod +x "$DEST/buzzness-tycoon"

echo "==> Building Windows (x86_64-windows) ..."
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
cp -f zig-out/bin/buzzness-tycoon.exe "$DEST/buzzness-tycoon.exe"

# Steamworks redistributables (achievements). Loaded at runtime from the
# game's folder; without them the game runs with local-only achievements.
for lib in linux64/libsteam_api.so win64/steam_api64.dll; do
  if [ -f "steam/redist/$lib" ]; then
    cp -f "steam/redist/$lib" "$DEST/$(basename "$lib")"
    echo "==> Bundled $lib"
  else
    echo "==> WARNING: steam/redist/$lib missing; Steam achievements will be local-only in this build"
  fi
done

echo "==> Staged:"
ls -lh "$DEST"
