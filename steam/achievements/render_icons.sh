#!/usr/bin/env bash
# Render the Steam achievement icons from the game's own sprites (ImageMagick).
# Each achievement gets an unlocked and a locked (greyed) icon at 64x64, plus a
# 256x256 master. Reproducible: re-run after editing; see docs/achievements.md
# for the achievement list (API names here must match src/achievements.zig).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

OUT=steam/achievements/icons
FONT=sprites/baloo2.ttf
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT/256" "$OUT/unlocked" "$OUT/locked"

# ---- palette (Catppuccin Mocha + the honey capsule gold) ---------------------
INK='#11111b'
TEXT='#cdd6f4'; BLUE='#89b4fa'; GREEN='#a6e3a1'; PINK='#f5c2e7'; PEACH='#fab387'
RED='#f38ba8'; YELLOW='#f9e2af'; TEAL='#94e2d5'; MAUVE='#cba6f7'; SAPPHIRE='#74c7ec'

# ---- sprite prep --------------------------------------------------------------
# Flower sheets are 5 growth frames of 32x32; the bloom is the last one.
for f in rose tulip dandelion; do
  magick sprites/$f.png -crop 32x32+128+0 +repage "$WORK/$f.png"
done
cp sprites/bee.png sprites/beehive.png sprites/grass-cube.png "$WORK/"
cp sprites/ui/cursor.png "$WORK/cursor.png"

# Hand-drawn crown / royal jelly sprites (sprites/crown.png, sprites/royal_jelly.png,
# 32x32 like the rest) replace the procedurally drawn fallbacks below when present.
crown_asset() { # W  -> path of a scaled crown sprite, or "" to use the fallback
  [ -f sprites/crown.png ] && sprite sprites/crown.png "$(($1 * 100 / 32))" || echo ""
}
jelly_asset() {
  [ -f sprites/royal_jelly.png ] && sprite sprites/royal_jelly.png "$(($1 * 100 / 32))" || echo ""
}

# tint SRC COLOR OUT — multiply the sprite by a colour, keeping its alpha
# (how the game tints the bee sprite per bee type).
tint() {
  magick "$1" \( +clone -alpha off -fill "$2" -colorize 100 \) -compose Multiply -composite \
    \( "$1" -alpha extract \) -alpha off -compose CopyOpacity -composite "$3"
}
tint "$WORK/bee.png" "$BLUE"  "$WORK/bee_swift.png"
tint "$WORK/bee.png" "$GREEN" "$WORK/bee_efficient.png"
tint "$WORK/bee.png" "$PINK"  "$WORK/bee_gardener.png"
# Rotten flower: the in-game grayscale post-tint.
magick "$WORK/rose.png" -colorspace Gray -modulate 70 "$WORK/rose_rotten.png"

# sprite FILE SCALE% [DX DY] — a pixel-scaled sprite with a soft drop shadow,
# ready for `-gravity center -geometry +DX+DY -composite`.
sprite() {
  local file=$1 scale=$2
  local key
  key="$(basename "$file" .png)_$scale"
  local out="$WORK/sp_$key.png"
  if [ ! -f "$out" ]; then
    # Hard offset shadow (no blur) so it stays pixel-crisp.
    magick "$file" -filter point -resize "$scale%" \
      \( +clone -fill "$INK" -colorize 100 -channel A -evaluate multiply 0.45 +channel -repage +6+6 \) +swap -background none -layers merge +repage "$out"
  fi
  echo "$out"
}

# label TEXT SIZE — outlined Baloo 2 caption, as a composite op string target.
label_png() {
  local txt=$1 size=$2
  local out="$WORK/label_$(echo "$txt" | tr -c 'A-Za-z0-9' '_')_$size.png"
  magick -background none -font "$FONT" -pointsize "$size" -fill white \
    -stroke "$INK" -strokewidth "$((size / 9))" label:"$txt" \
    \( +clone -stroke none -fill white label:"$txt" \) -gravity center -composite \
    "$out"
  echo "$out"
}

# crown W COLOR GEM — the prestige crown from src/ui/icons.zig as a PNG.
crown_png() {
  local w=$1 color=$2 gem=$3
  local out="$WORK/crown_$w.png"
  local asset; asset="$(crown_asset "$w")"
  if [ -n "$asset" ]; then echo "$asset"; return; fi
  local h=$((w * 8 / 10)) cx=$((w / 2))
  local cy=$((w * 8 / 20))
  local left=0 right=$w
  local bandTop=$((cy + h * 15 / 100)) bottom=$((cy + h / 2)) tipY=$((cy - h / 2)) midTipY=$((cy - h * 6 / 10))
  local gemR=$((w * 9 / 100))
  magick -size "${w}x${w}" xc:none -fill "$color" \
    -draw "rectangle $left,$bandTop $right,$bottom" \
    -draw "polygon $left,$((bandTop + 1)) $left,$tipY $((cx - w * 16 / 100)),$((bandTop + 1))" \
    -draw "polygon $((cx - w * 28 / 100)),$((bandTop + 1)) $cx,$midTipY $((cx + w * 28 / 100)),$((bandTop + 1))" \
    -draw "polygon $((cx + w * 16 / 100)),$((bandTop + 1)) $right,$tipY $right,$((bandTop + 1))" \
    -fill "$gem" \
    -draw "circle $((left + gemR * 4 / 10)),$tipY $((left + gemR * 4 / 10 + gemR)),$tipY" \
    -draw "circle $cx,$midTipY $((cx + gemR * 12 / 10)),$midTipY" \
    -draw "circle $((right - gemR * 4 / 10)),$tipY $((right - gemR * 4 / 10 + gemR)),$tipY" \
    "$out"
  echo "$out"
}

# drop W COLOR — honey/jelly drop (icons.drawHoneyDrop): bead + pointed top.
drop_png() {
  local w=$1 color=$2
  local out="$WORK/drop_${w}_$(echo "$color" | tr -d '#').png"
  local asset; asset="$(jelly_asset "$w")"
  if [ -n "$asset" ]; then echo "$asset"; return; fi
  local r=$((w * 36 / 100)) cx=$((w / 2)) cy=$((w * 62 / 100))
  magick -size "${w}x${w}" xc:none -fill "$color" \
    -draw "polygon $cx,$((cy - r - r * 8 / 10)) $((cx - r * 72 / 100)),$((cy - r / 2)) $((cx + r * 72 / 100)),$((cy - r / 2))" \
    -draw "circle $cx,$cy $((cx + r)),$cy" \
    -fill 'rgba(255,250,220,0.75)' -draw "circle $((cx - r * 35 / 100)),$((cy - r * 35 / 100)) $((cx - r * 35 / 100 + r * 22 / 100)),$((cy - r * 35 / 100))" \
    "$out"
  echo "$out"
}

# icon NAME COLOR [composite ops...] — flat solid background, then whatever
# layers follow, saved as the 256 master.
icon() {
  local name=$1 color=$2; shift 2
  # -strip drops the date chunks so unchanged icons re-render byte-identical.
  magick -size 256x256 xc:"$color" "$@" -strip "$OUT/256/$name.png"
}

# Solid background per family.
BRONZE='#c98a5a'; HONEY='#f6bd45'; GOLD='#f2c744'; DIAMOND='#8fd0f0'
MEADOW='#8fce7c'; ROYAL='#e39ad0'; SKY='#89b4fa'; SEA='#7fd6c6'
GRAPE='#b48ef0'; EMBER='#d8843a'; NIGHT='#1c1a3c'; ALARM='#e87a95'

bg() { echo "$1"; }

# ---- honey milestones ---------------------------------------------------------
icon first_drop     $(bg "$BRONZE") \( "$(sprite "$WORK/beehive.png" 460)" \) -gravity center -geometry +0-30 -composite \( "$(label_png 1K 64)" \) -gravity south -geometry +0+10 -composite
icon local_business $(bg "$HONEY")  \( "$(sprite "$WORK/beehive.png" 460)" \) -gravity center -geometry +0-30 -composite \( "$(label_png 100K 58)" \) -gravity south -geometry +0+12 -composite
icon liquid_gold    $(bg "$GOLD")   \( "$(sprite "$WORK/beehive.png" 460)" \) -gravity center -geometry +0-30 -composite \( "$(label_png 1M 64)" \) -gravity south -geometry +0+10 -composite
icon bee_llionaire  $(bg "$DIAMOND") \( "$(sprite "$WORK/beehive.png" 460)" \) -gravity center -geometry +0-30 -composite \( "$(label_png 1B 64)" \) -gravity south -geometry +0+10 -composite

# ---- super flowers ------------------------------------------------------------
# Super Bloom: one SUPER (double-size) rose with sparkles.
icon super_bloom $(bg "$MEADOW") \( "$(sprite "$WORK/rose.png" 650)" \) -gravity center -geometry +0+6 -composite \
  -fill white -draw "circle 58,52 58,58" -draw "circle 200,70 200,74" -draw "circle 186,178 186,181" -draw "circle 66,190 66,193"
# Field of Giants: a 2x2 block of SUPER flowers.
icon field_of_giants $(bg "$MEADOW") \
  \( "$(sprite "$WORK/dandelion.png" 330)" \) -gravity northwest -geometry +18+18 -composite \
  \( "$(sprite "$WORK/rose.png" 330)" \) -gravity northeast -geometry +18+18 -composite \
  \( "$(sprite "$WORK/tulip.png" 330)" \) -gravity southwest -geometry +18+26 -composite \
  \( "$(sprite "$WORK/rose.png" 330)" \) -gravity southeast -geometry +18+26 -composite
# Botanical Trifecta: rose + tulip + dandelion side by side.
icon botanical_trifecta $(bg "$MEADOW") \
  \( "$(sprite "$WORK/rose.png" 300)" \) -gravity center -geometry -82+8 -composite \
  \( "$(sprite "$WORK/tulip.png" 300)" \) -gravity center -geometry +0-6 -composite \
  \( "$(sprite "$WORK/dandelion.png" 300)" \) -gravity center -geometry +82+8 -composite

# ---- prestige -----------------------------------------------------------------
icon long_live_the_queen $(bg "$ROYAL") \( "$(crown_png 118 "$YELLOW" "$PINK")" \) -gravity center -geometry +0-58 -composite \( "$(sprite "$WORK/bee.png" 500)" \) -gravity center -geometry +0+34 -composite
icon dynasty   $(bg "$ROYAL") \( "$(crown_png 150 "$YELLOW" "$PINK")" \) -gravity center -geometry +0-28 -composite \( "$(label_png x5 60)" \) -gravity south -geometry +0+10 -composite
icon perennial $(bg "$ROYAL") \( "$(crown_png 150 "$YELLOW" "$PINK")" \) -gravity center -geometry +0-28 -composite \( "$(label_png x10 60)" \) -gravity south -geometry +0+10 -composite
icon royal_treatment $(bg "$ROYAL") \( "$(drop_png 150 "$PINK")" \) -gravity center -geometry +0-22 -composite \( "$(label_png 100 56)" \) -gravity south -geometry +0+10 -composite

# ---- colony -------------------------------------------------------------------
# Full Crew: the four bee types.
icon full_crew $(bg "$HONEY") \
  \( "$(sprite "$WORK/bee.png" 340)" \) -gravity center -geometry -50-48 -composite \
  \( "$(sprite "$WORK/bee_swift.png" 340)" \) -gravity center -geometry +50-48 -composite \
  \( "$(sprite "$WORK/bee_efficient.png" 340)" \) -gravity center -geometry -50+52 -composite \
  \( "$(sprite "$WORK/bee_gardener.png" 340)" \) -gravity center -geometry +50+52 -composite
# Hive Mind: a 3x3 formation.
hive_mind_ops=()
for dy in -70 0 70; do for dx in -70 0 70; do
  hive_mind_ops+=( \( "$(sprite "$WORK/bee.png" 210)" \) -gravity center -geometry "$(printf '%+d%+d' $dx $dy)" -composite )
done; done
icon hive_mind $(bg "$HONEY") "${hive_mind_ops[@]}"
# BZZZZZZZZZZZZZ: a swarm.
swarm_ops=()
for dy in -84 -42 0 42 84; do for dx in -84 -42 0 42 84; do
  swarm_ops+=( \( "$(sprite "$WORK/bee.png" 125)" \) -gravity center -geometry "$(printf '%+d%+d' $dx $((dy - 12)))" -composite )
done; done
icon swarm $(bg "$EMBER") "${swarm_ops[@]}" \( "$(label_png 1M 60)" \) -gravity south -geometry +0+4 -composite
icon wholesale $(bg "$SEA") \( "$(sprite "$WORK/bee.png" 500)" \) -gravity center -geometry +0-26 -composite \( "$(label_png x100 58)" \) -gravity south -geometry +0+10 -composite
# Circle of Life: a gardener over a rotten flower.
icon circle_of_life $(bg "$MEADOW") \( "$(sprite "$WORK/rose_rotten.png" 450)" \) -gravity center -geometry -30+30 -composite \( "$(sprite "$WORK/bee_gardener.png" 380)" \) -gravity center -geometry +44-40 -composite

# ---- upgrade tree -------------------------------------------------------------
# Well Read: three tree nodes (tree_view style) joined by branches.
icon well_read $(bg "$GRAPE") \
  -stroke "$TEAL" -strokewidth 8 -draw "line 128,88 64,176" -draw "line 128,88 192,176" -stroke none \
  -fill '#313244' -stroke "$TEAL" -strokewidth 5 \
  -draw "roundrectangle 88,40 168,120 14,14" -draw "roundrectangle 26,146 106,226 14,14" -draw "roundrectangle 150,146 230,226 14,14" -stroke none \
  \( "$(sprite "$WORK/beehive.png" 200)" \) -gravity center -geometry +0-48 -composite \
  \( "$(sprite "$WORK/bee.png" 200)" \) -gravity center -geometry -62+58 -composite \
  \( "$(sprite "$WORK/rose.png" 200)" \) -gravity center -geometry +62+58 -composite
# Land Baron: a 2x2 block of meadow tiles.
icon land_baron $(bg "$SKY") \
  \( "$(sprite "$WORK/grass-cube.png" 400)" \) -gravity northwest -geometry +64+8 -composite \
  \( "$(sprite "$WORK/grass-cube.png" 400)" \) -gravity northwest -geometry +0+40 -composite \
  \( "$(sprite "$WORK/grass-cube.png" 400)" \) -gravity northwest -geometry +128+40 -composite \
  \( "$(sprite "$WORK/grass-cube.png" 400)" \) -gravity northwest -geometry +64+72 -composite

# ---- hidden easter eggs -------------------------------------------------------
# Night Shift: bee under the moon and stars.
icon night_shift $(bg "$NIGHT") \
  -fill '#f5f0d8' -draw "circle 196,58 196,88" -fill "$NIGHT" -draw "circle 210,50 210,76" \
  -fill white -draw "circle 40,44 40,47" -draw "circle 90,30 90,32" -draw "circle 60,110 60,112" -draw "circle 150,100 150,102" -draw "circle 220,150 220,152" -draw "circle 30,170 30,172" \
  \( "$(sprite "$WORK/bee.png" 520)" \) -gravity center -geometry +0+24 -composite
# Don't Poke the Hive: the cursor jabbing the hive.
icon dont_poke_the_hive $(bg "$ALARM") \( "$(sprite "$WORK/beehive.png" 520)" \) -gravity center -geometry -16+0 -composite \( "$(sprite "$WORK/cursor.png" 520)" \) -gravity center -geometry +52+44 -composite
# Sticky Situation: hive with a full, red storage bar.
icon sticky_situation $(bg "$HONEY") \( "$(sprite "$WORK/beehive.png" 480)" \) -gravity center -geometry +0-26 -composite \
  -fill "$INK" -draw "roundrectangle 30,190 226,226 10,10" -fill "$RED" -draw "roundrectangle 36,196 220,220 8,8"

# ---- locked variants + 64px outputs + contact sheet ---------------------------
for f in "$OUT"/256/*.png; do
  name="$(basename "$f")"
  magick "$f" -colorspace Gray -brightness-contrast -22x-28 -fill '#1e1e2e' -colorize 30 "$WORK/locked_$name"
  magick "$f" -filter Box -resize 64x64 -strip "$OUT/unlocked/$name"
  magick "$WORK/locked_$name" -filter Box -resize 64x64 -strip "$OUT/locked/$name"
done

# Contact sheet in Steamworks display order (same as src/achievements.zig).
ORDER=(first_drop super_bloom full_crew local_business hive_mind wholesale long_live_the_queen liquid_gold field_of_giants botanical_trifecta circle_of_life land_baron well_read royal_treatment dynasty perennial bee_llionaire swarm night_shift dont_poke_the_hive sticky_situation)
tiles=()
for n in "${ORDER[@]}"; do
  [ -f "$OUT/256/$n.png" ] || { echo "missing icon for $n" >&2; exit 1; }
  tiles+=( -label "$n" "$OUT/256/$n.png" )
done
magick montage "${tiles[@]}" -font "$FONT" -pointsize 16 -tile 7x -geometry 128x128+12+10 -background '#1e1e2e' -fill '#cdd6f4' -strip "$OUT/contact_sheet.png"
ltiles=()
for n in "${ORDER[@]}"; do ltiles+=( -label "$n" "$WORK/locked_$n.png" ); done
magick montage "${ltiles[@]}" -font "$FONT" -pointsize 16 -tile 7x -geometry 128x128+12+10 -background '#1e1e2e' -fill '#cdd6f4' -strip "$OUT/contact_sheet_locked.png"

echo "Rendered $(ls "$OUT"/unlocked | wc -l) achievements -> $OUT/{256,unlocked,locked}/ + contact sheets"
