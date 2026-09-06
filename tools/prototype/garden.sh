#!/usr/bin/env bash
# Disposable, native layout experiment. Never reads the normal game save.
set -euo pipefail
cd "$(dirname "$0")/../.."
garden_scratch=$(mktemp -d /tmp/bt-garden-XXXXXX)
trap 'rm -rf "$garden_scratch"' EXIT
cat > "$garden_scratch/save.txt" <<'SAVE'
BUZZNESS_TYCOON 1
resources 1500 3000 1 0 0 10 1
hive 1 20
grid 17 17
prestige 0 0 0
labs 1 0 0 0
jelly_spent 0
upgrade 6
upgrade 27
upgrade 28
bees 0 12
bees 3 4
END
SAVE
BT_POC_GARDEN=1 BT_STEAM=0 BT_WINDOWED=1 BT_AUTOPLAY=1 BT_SAVE_PATH="$garden_scratch/save.txt" zig build run -Doptimize=ReleaseFast
