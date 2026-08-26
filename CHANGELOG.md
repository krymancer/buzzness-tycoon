# Changelog

## 0.3.1 — 2026-08-26

### Performance: million-bee colonies — issue #59
- **Dense bee store** (`src/bees.zig`): bees are no longer ECS entities.
  Positions, AI state, pollen and lifespans live in one struct-of-arrays
  list swept linearly every frame — no per-bee hash lookups anywhere
  (simulation, rendering, saving, per-frame type census).
- **Simulation cap with a dormant surplus**: at most 50,000 bees are
  simulated; the rest of the colony is counted, saved and shown but not
  iterated. The simulated mix stays proportional to the colony (at least one
  of every owned type) and is rebalanced whenever purchases or deaths change
  it. Honey is unchanged — income is bounded by flower pollen, and the cap
  exceeds the claim slots of the largest meadow. Headless bench
  (`just sim-bench`): 1M bees on a 41x41 meadow, 0.31 ms per update frame
  (was ~262 ms per frame in the 2026-08-25 measurement).
- **Bees stay on the meadow**: idle bees that wander more than two tiles
  past the edge turn back toward the hive instead of blanketing the window.
- **Flower search scales with the meadow**: the target cache is sized for
  the largest grid (was capped at 512 flowers) and indexed by cell, so a
  bee scans the tiles around it rather than the whole cache; flowers past
  the first 512 are also drawn now, and off-screen flowers are culled.
- **Caps raised**: colony ceiling 1,000,000,000 per type (was 100,000 per
  type / 100,000 total on load); Grid Ring max level 10 → 20 and Royal
  Meadow 8 → 12 (largest meadow 81x81). "Land Baron" (max out Grid Ring)
  now requires level 20.
- **Wholesale Contract** (Royal Shop, 300 RJ, x2 per level, 4 levels): one
  more bulk-buy quantity step per level beyond Bulk Order's x1000 — x5000,
  x10K, x50K, x100K bees per click. A prestige perk, so it survives runs.
- **Seed Scouts** (bees branch, replaces Cleanup Crew at 15000): idle
  gardeners seek out empty tiles and fly there to plant — rot first, gaps
  second, pollen last. **Composting** now also does what Cleanup Crew did
  (gardeners hunt rotten flowers). Saves that owned Cleanup Crew own Seed
  Scouts.
- Dev: `zig build bench -- [bees] [grid] [frames]` / `just sim-bench`
  (headless update-side benchmark), `just swarm [bees]` (windowed run on a
  staged 1M-bee save), `sim N` line in the debug readout.

## 0.3.0 — 2026-08-26

### Achievements (Steam) — issue #53
- **Lifetime stats layer** in the save file (`stat` lines): lifetime honey,
  prestige count, SUPER flowers merged, rotten flowers cleared by gardeners,
  max bees alive. Profile-level: survive prestige and New Game.
- **21 achievements** (`src/achievements.zig`, EN + PT-BR copy): honey
  milestones, super flowers, prestige, colony, upgrade tree, and three hidden
  easter eggs. Unlocks persist in the save (`achievement` lines) and show an
  in-game banner; `docs/achievements.md` is the generated Steamworks sheet.
- **Steamworks binding at runtime** (`src/steam.zig`): loads
  `libsteam_api.so` / `steam_api64.dll` next to the executable, mirrors the
  stats and pushes unlocks; silent no-op without the library or Steam.
- Dev: `just achievements` (staged save one step from several unlocks),
  `just steam-dev`, `BT_STEAM=0`, `BT_RESET_ACHIEVEMENTS=1`,
  `just achievement-icons` (renders the 64×64 icons from game sprites).

## 0.2.6 — 2026-08-24

### New upgrades
- **Cleanup Crew** (bees branch, after Composting): gardener bees actively hunt
  rotten flowers and fly there to clear them.
- **Colony vitality column** (under Storage; buyable from the start, infinitely
  repeatable): **Fertile Soil** — flowers mature and re-pollen ×1.2/level;
  **Bee Vitality** — bees live ×1.2/level (already-living bees benefit too);
  **Hardy Blooms** — rot chance ×0.85/level.
- **Bulk Order** (grid column): level 1 adds ×50 to the bee buy cycle,
  level 2 adds ×100.

### Fixes
- D-pad / number-key quick buys now honor the selected ×10/×25 bulk quantity
  (they always bought a single bee before).

### UI
- Upgrade tree redesign: compact one-row nodes (effect icon + name + cost),
  the whole tree is ~25% shorter.
- Hovering a tree node shows a description tooltip with a live "Now → Next"
  line computed from the same formulas the game applies.
- All big numbers use the short honey format now (bee census, honey factor,
  rate, prestige totals): +675731072.0/s reads +675.73M/s.

## 0.2.1 — 2026-08-23

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
