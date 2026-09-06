# Buzzness Tycoon dev recipes. `just` lists them; `just <recipe>` runs one.
#
# The game reads a handful of BT_* env vars as dev hooks (windowed run, skip
# the title, open a modal, freeze the time of day, screenshot and exit). The
# recipes below are mostly named bundles of those so nobody has to remember
# them. Screenshot/capture recipes need a live display.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Windowed dev size (BT_W/BT_H switch to an undecorated pinned window).
dev_env := "BT_WINDOWED=1 BT_AUTOPLAY=1"
# Store-asset size, clean HUD.
shot_env := "BT_WINDOWED=1 BT_W=1920 BT_H=1080 BT_HIDE_DEBUG=1 BT_AUTOPLAY=1"

default:
    @just --list --unsorted

# ---- build / verify ---------------------------------------------------------

# Debug build into zig-out/
build:
    zig build

# Optimized native build
release:
    zig build -Doptimize=ReleaseFast

# Cross-compile the Windows binary
windows:
    zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast

# Compile check without linking (fast, editor-on-save friendly)
check:
    zig build check

# Unit tests
test:
    zig build test

# Format all sources in place
fmt:
    zig fmt src/ build.zig

# Fail if anything is unformatted (what CI wants)
fmt-check:
    zig fmt --check src/ build.zig

# fmt-check + check + test — run before pushing
ci: fmt-check check test

# ---- run ---------------------------------------------------------------------

# Run normally (title screen, saved window mode)
run:
    zig build run

# Windowed run straight into the meadow, skipping the title
dev:
    {{dev_env}} zig build run

# Windowed run with a modal open: tree | options | prestige | plant (plant takes x,y)
open modal coords="0,0":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{modal}}" in
        tree)     extra="BT_OPEN_TREE=1" ;;
        options)  extra="BT_OPEN_OPTIONS=1" ;;
        prestige) extra="BT_OPEN_PRESTIGE=1" ;;
        plant)    extra="BT_OPEN_PLANT={{coords}}" ;;
        *) echo "unknown modal '{{modal}}' (tree|options|prestige|plant)"; exit 1 ;;
    esac
    env {{dev_env}} $extra zig build run

# Windowed run at a fixed time of day (0.28 sunrise, 0.5 noon, 0.74 sunset, 0.97 night)
at phase:
    {{dev_env}} BT_PHASE={{phase}} zig build run

# Run against a throwaway save so the real one stays untouched
scratch path="/tmp/bt_scratch_save.txt":
    {{dev_env}} BT_SAVE_PATH={{path}} zig build run

# Windowed run on a staged swarm save: N bees (default 1M) on a 41x41
# meadow, FPS readout on, honey to keep buying. Issue #59 reproduction.
swarm bees="1000000":
    #!/usr/bin/env bash
    set -euo pipefail
    save=/tmp/bt_swarm_save.txt
    cat > "$save" <<EOF
    BUZZNESS_TYCOON 1
    resources 500000000 1000000000 1 0 0 10 1
    hive 32 20
    grid 41 41
    prestige 120000 0 1
    labs 1 0 0 0
    upgrade 19
    upgrade 4
    upgrade 5
    upgrade 6
    level 10 12
    upgrade 32
    level 32 4
    shop 5 4
    bees 0 $(( {{bees}} * 85 / 100 ))
    bees 1 $(( {{bees}} * 5 / 100 ))
    bees 2 $(( {{bees}} * 5 / 100 ))
    bees 3 $(( {{bees}} * 5 / 100 ))
    END
    EOF
    env {{dev_env}} BT_SAVE_PATH="$save" BT_SHOW_DEBUG=1 zig build run -Doptimize=ReleaseFast

# Headless simulation benchmark (no window): bees, grid side, frames
sim-bench bees="1000000" grid="41" frames="600":
    zig build bench -Doptimize=ReleaseFast -- {{bees}} {{grid}} {{frames}}

# Windowed run on a staged late-game save (prestige unlocked, jelly to spend, bulk buy maxed)
late-game:
    #!/usr/bin/env bash
    set -euo pipefail
    save=/tmp/bt_late_game_save.txt
    cat > "$save" <<'EOF'
    BUZZNESS_TYCOON 1
    resources 5000000 10000000 1 120000000 0 10 1
    hive 32 20
    grid 21 21
    prestige 120000 3940000000000 1
    labs 1 0 0 0
    jelly_spent 500
    shop 0 3
    shop 2 1
    upgrade 19
    upgrade 4
    upgrade 5
    upgrade 6
    upgrade 10
    level 10 2
    upgrade 32
    level 32 4
    bees 0 40
    bees 1 20
    END
    EOF
    env {{dev_env}} BT_SAVE_PATH="$save" BT_OPEN_PRESTIGE=1 zig build run

# Windowed run on a save staged one step from several achievements: 99 bees
# (buy one -> Hive Mind), 990 lifetime honey (First Drop), swift+efficient
# owned (buy a gardener -> Full Crew), bulk buy x100 unlocked (Wholesale),
# Grid Ring 9 (Land Baron), Night Shift 3. Unlocks log to stderr + banner.
achievements:
    #!/usr/bin/env bash
    set -euo pipefail
    save=/tmp/bt_achievements_save.txt
    cat > "$save" <<'EOF'
    BUZZNESS_TYCOON 1
    resources 400000 500000 1 0 0 10 1
    hive 8 20
    grid 35 35
    prestige 40 0 1
    labs 1 0 0 0
    stat lifetime_honey 990
    stat prestige_count 0
    stat super_flowers_merged 0
    stat rotten_cleared 48
    stat max_bees_alive 99
    upgrade 19
    upgrade 4
    upgrade 5
    upgrade 6
    upgrade 27
    upgrade 28
    level 10 9
    level 32 4
    level 33 3
    bees 0 97
    bees 1 1
    bees 2 1
    END
    EOF
    env {{dev_env}} BT_SAVE_PATH="$save" BT_RESET_ACHIEVEMENTS=1 zig build run

# Windowed run against the real Steam client: needs the Steamworks SDK's
# redistributable_bin copied to steam/redist/ and Steam running
steam-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    echo 4980570 > steam_appid.txt
    [ -f steam/redist/linux64/libsteam_api.so ] || echo "warning: steam/redist/linux64/libsteam_api.so not found; running with the local backend only"
    env {{dev_env}} zig build run

# Regenerate docs/achievements.md (Steamworks entry sheet) and the Steamworks
# localization VDF/zip files (steam/achievements/loc/) from src/achievements.zig
achievements-sheet:
    zig build achievements-sheet

# Regenerate the achievement icons (ImageMagick) into steam/achievements/icons/
achievement-icons:
    bash steam/achievements/render_icons.sh

# Run in Portuguese regardless of the system locale
pt:
    {{dev_env}} BT_LANG=pt zig build run

# Run with the FPS/frametime readout, uncapped, for perf checks
bench frames="600":
    {{dev_env}} BT_SHOW_DEBUG=1 BT_UNCAPPED=1 BT_SHOOT={{frames}} zig build run

# ---- screenshots / trailer (need a display) ----------------------------------

# Render N frames of a windowed run and write bt_shot.png (~60 frames/s of sim)
shoot frames="120" phase="0.5":
    {{dev_env}} BT_HIDE_DEBUG=1 BT_PHASE={{phase}} BT_SHOOT={{frames}} zig build run
    @echo "-> bt_shot.png"

# Same, with a modal open (tree | options | prestige)
shoot-modal modal frames="60":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{modal}}" in
        tree)     extra="BT_OPEN_TREE=1" ;;
        options)  extra="BT_OPEN_OPTIONS=1" ;;
        prestige) extra="BT_OPEN_PRESTIGE=1" ;;
        *) echo "unknown modal '{{modal}}' (tree|options|prestige)"; exit 1 ;;
    esac
    env {{dev_env}} BT_HIDE_DEBUG=1 BT_PHASE=0.5 $extra BT_SHOOT={{frames}} zig build run
    echo "-> bt_shot.png"

# 1920x1080 store screenshot; lush blooms take ~2200 frames (~36s of sim)
shoot-store phase="0.5" frames="2200":
    {{shot_env}} BT_PHASE={{phase}} BT_SHOOT={{frames}} zig build run
    @echo "-> bt_shot.png (move it into steam/screenshots/)"

# Trailer frames: 36s day->night arc at 30fps into steam/art/frames/
capture frames="1080":
    mkdir -p steam/art/frames
    {{shot_env}} BT_DAYLEN=30 BT_CAPTURE={{frames}} zig build run

# Regenerate Steam capsule art from the HTML templates (headless Chrome)
capsules:
    bash steam/art/render.sh

# ---- steam -------------------------------------------------------------------

# Build Linux + Windows in ReleaseFast and stage them into steam/content/all/
stage:
    bash steam/stage.sh

# Push the staged depot with steamcmd (needs STEAM_USER; never auto-publishes)
upload:
    bash steam/upload.sh

# ---- housekeeping -----------------------------------------------------------

# Print where this machine's save lives
save-path:
    @echo "${XDG_DATA_HOME:-$HOME/.local/share}/buzzness-tycoon/save.txt"

# Back up the real save next to itself with a timestamp
save-backup:
    #!/usr/bin/env bash
    set -euo pipefail
    p="${XDG_DATA_HOME:-$HOME/.local/share}/buzzness-tycoon/save.txt"
    cp -v "$p" "$p.$(date +%Y%m%d-%H%M%S).bak"

# Remove build caches and dev screenshot output
clean:
    rm -rf zig-out .zig-cache bt_shot.png

# Disposable native flower-layout experiment (this prototype branch only)
poc-garden:
    bash tools/prototype/garden.sh
