# Changelog

## Unreleased (next version — bump title-screen version before release)

Merged in PRs #31, #34, #35, #36, #37. Steam Deploy workflow in PR #32.

### Progression & balance
- **Repeatable upgrades**: tree nodes can now be bought again to level up
  (geometric cost growth). Owned repeatables show `Name LvN` + next cost.
- **Honey**: new Honey x16 (3.5K) and Honey x32 (10K) nodes, plus repeatable
  **Honey Boost** (+25%/level, 8K ×1.5/level, uncapped).
- **Aura rework**: *Lab: Aura* is repeatable (+25% honey per level) and a new
  repeatable *Aura Reach* widens its radius (+1 tile/level, base 4). The Aura
  bonus now applies only to pollen from flowers inside the rings around the
  hive — the rings are gameplay, not decoration.
- **Burst and Bloom removed**; late-game buffs come from Instant Grow and Aura.
  Prestige now requires Aura Reach + Super Flowers.
- **Grow Speed / Grid Ring / Storage** collapsed from 3-node chains into single
  repeatable nodes (Grow: −1s/level down to 2s, 8 levels; Grid: +1 ring/level,
  10 levels; Storage: +500×1.6^level, uncapped). Old saves fold the legacy
  nodes into levels automatically.
- **Storage cap enabled** (it was silently disabled): honey stops at capacity,
  so Storage upgrades matter.
- **Flower spawning scales with meadow size** — fixes the ~500/s ceiling where
  the field stalled at ~25 flowers regardless of grid size.
- **Green Thumb** (repeatable, 8 levels): gardener plant chance 20% → +10%/level.
- **Composting** (one-shot): gardener bees clear rotten flowers they fly over.
- **Bulk bee buying**: ×1 / ×10 / ×25 chips in the shop (Shift-click = ×10).
- All flower types cost 10 to plant (they play identically).

### New mechanics
- **Rotten flowers**: when a mature flower's life ends it has a 60% chance to
  wither in place (grayscale, no pollen, blocks the cell). Click it to clear.
  Replaces the old "click the heart" rebirth bubble.
- **Plant chooser**: click an empty tile to plant a Dandelion / Rose / Tulip.
- The old tile popup (hive honey ×2 upgrade, per-flower upgrade, popup bee
  buying) is removed — the tree and side panel are the single upgrade path.

### UI
- **Aura pulse**: expanding lavender rings on the meadow around the hive;
  reach and ring count grow with Aura levels.
- **Sidebar footer**: Aura / Instant Grow status rows standardized as
  `[icon] Name: state`; Labs text removed from the left HUD.
- **HUD**: honey icon sized to the digits and vertically centred; reads
  `honey / capacity  ×factor  (+rate/s)` with a storage meter underneath
  (red + "STORAGE FULL" at the cap).
- **Title screen**: *Continue* / *New Game* when a save exists; New Game asks
  "Are you sure?" on a second click.
- Tree view: teal border on owned repeatables you can afford to level.

### Options & window
- **Options screen** (title screen and pause menu, replacing the language
  button): Window mode, Language, Volume slider, UI scale slider. Window mode
  and volume persist in the save.
- **Window modes**: Windowed / **Borderless** (default; Alt-Tab friendly) /
  Fullscreen (exclusive, for people who want true fullscreen). Alt+Enter
  toggles windowed ↔ the chosen mode. On macOS borderless keeps the menu bar
  visible (trade-off accepted for now).
- **Fixed mouse offset on Windows** in windowed/borderless modes at 125/150%
  display scaling (raylib reports the mouse in physical pixels there, in points
  on macOS).
- **Upgrade tree fits the panel** at large UI scales (layout scales down to
  60%), and scrolls/drag-pans when it still overflows.

### Saves
- New `level <id> <n>` lines; `is_rotten` flower flag. Old saves load.

### Dev / CI
- `BT_OPEN_TREE=1`, `BT_OPEN_PLANT=x,y`, `BT_OPEN_OPTIONS=1` open those UIs at
  start (screenshots).
- GitHub Actions bumped to Node 24 releases; `mlugg/setup-zig`.
- Manual **Steam Deploy** workflow (Actions → Steam Deploy → release tag).

### Known / next
- Per-bee-type upgrades (decide: flat vs. scaling bee prices).
- Tree node descriptions/tooltips; action-button layout + keyboard shortcuts;
  prestige rework.
- Balance knobs to watch after play-testing: `SPAWN_ROLLS_PER_CELL`
  (flower_spawning_system.zig), `ROT_CHANCE_PERCENT` (lifespan_system.zig),
  Lab: Aura 8K entry cost, starting storage cap 500.
