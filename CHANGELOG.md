# Changelog

## Unreleased (next version — bump title-screen version before release)

Merged in PR #31 (`feat/repeatable-upgrades`). Steam Deploy workflow in PR #32.

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

### Window
- **Borderless windowed instead of exclusive fullscreen** so Alt-Tab works
  (raylib #3865 / #4655 background). Alt+Enter toggles to a 1280×720 window.
  On macOS the menu bar stays visible (trade-off accepted for now).

### Saves
- New `level <id> <n>` lines; `is_rotten` flower flag. Old saves load.

### Dev
- `BT_OPEN_TREE=1`, `BT_OPEN_PLANT=x,y` open those UIs at start (screenshots).

### Known / next
- Per-bee-type upgrades (decide: flat vs. scaling bee prices).
- Tree node descriptions/tooltips; action-button layout + keyboard shortcuts;
  prestige rework.
- Balance knobs to watch after play-testing: `SPAWN_ROLLS_PER_CELL`
  (flower_spawning_system.zig), `ROT_CHANCE_PERCENT` (lifespan_system.zig),
  Lab: Aura 8K entry cost, starting storage cap 500.
