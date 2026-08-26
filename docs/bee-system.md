# Bee System

> **⚠️ LEGACY DOCUMENTATION**  
> This document describes the old OOP-based bee implementation that has been replaced by the ECS architecture.  
> For current implementation, see:
> - [ECS Refactor Plan](./ecs-refactor-plan.md) - Current ECS architecture
> - [Game Engine](./game-engine.md) - ECS system execution order
> - Components: `BeeAI`, `Position`, `PollenCollector`, `Lifespan` in `src/ecs/components.zig`
> - System: `bee_ai_system.zig` for current bee behavior

## Current Bee Behavior

### Overview
Bees live in a dense struct-of-arrays store, `World.bees` (`src/bees.zig`),
not in the entity/component tables: nothing refers to a bee by id, every
bee carries the same fields (`Position`, `BeeAI`, `PollenCollector`,
`Lifespan`) and the simulation touches all of them every frame, so a linear
sweep with no hash lookups is the right shape. All behavior is in
`bee_ai_system.zig`.

### Colony scale (issue #59)
- **Simulation cap** — at most `bees.SIM_CAP` (50,000) bees are simulated
  individually. The store tracks the true colony size per type
  (`population`); bees past the cap are *dormant*: counted, saved, shown in
  the HUD and achievements, never iterated.
- **Proportional representation** — the simulated mix follows the colony
  (`bees.apportion`, largest-remainder rounding, at least one representative
  of every owned type). Purchases past the cap and deaths mark the store
  dirty; the bee system rebalances at the start of the next frame, retiring
  idle bees first so no pollen in flight is lost.
- **Why honey stays exact** — income is bounded by flower pollen (each
  flower with pollen takes at most `MAX_BEES_PER_FLOWER` = 3 claims per
  refill), not by bee count. The cap is above the claim slots of the largest
  meadow, so a saturated colony earns exactly what the per-bee sim would.
  Scaling a representative's delivery by `population / simulated` (the
  "virtual bee" scheme) would instead multiply late-game income by that
  factor. The one place weighting *is* used: a representative gardener's
  planting roll is `1 - (1-p)^weight`, the chance that any of the gardeners
  it stands for would have planted (`effectivePlantChance`).
- **Meadow tether** — untargeted bees random-walk, but more than
  `WANDER_MARGIN_TILES` (2) past the meadow's edge they turn back toward the
  hive, so an idle swarm hovers over the field instead of tiling the window.
- **Flower search** — the per-frame flower cache is sized for the largest
  meadow and indexed by grid cell; a searching bee scans the 13x13 cells
  around its own tile and falls back to a bounded random sample of the cache,
  so search cost is independent of meadow size.
- **Bench** — `just sim-bench [bees] [grid] [frames]` runs the update side
  headlessly (`src/bench.zig`). 2026-08-26, ReleaseFast on a desktop Linux
  box: 1M bees on 41x41 = 0.31 ms/frame; on 81x81 (Grid Ring 20 + Royal
  Meadow 12) = 0.42 ms; on the 127x127 save guard = 0.67 ms. Honey/s is
  identical for 50k and 1M bees and within noise of 5k bees (all three
  saturate the meadow's flowers).
- **Rendering** — `render_system` sweeps the store, frustum-culls and draws
  at most 32,768 bees in three batched passes, all at the shared sprite
  scale `gridScale / 3`.
- **Save** — `bees <type> <count>` lines carry the whole colony; `bee` cell
  lines only the simulated bees' tiles. Loading restores the cells, sets the
  population from the counts (falling back to the cell sums for saves from
  before the split) and rebalances.

### Key Features
- **Per-frame flower caching** - Available flowers cached every 4th frame, spatially indexed
- **Stagger groups** - Each bee takes its full decision step every 4th frame (with a 4x delta) and interpolates in between
- **Scatter behavior** - Bees dawdle 0.6-1.4 s after collecting pollen
- **Density limiting** - Maximum 3 bees per flower target
- **Beehive targeting** - Bees return to deposit pollen at the central beehive
- **Life extension** - +50% lifespan when carrying pollen at death (bees are immortal by `config.bees_immortal`; aging is skipped entirely then)
- **Pollination** - Gardeners plant on empty cells they cross (Green Thumb raises the chance); with Seed Scouts, idle gardeners seek out gaps and plant them for sure (rot → gaps → pollen)
- **Search cooldown** - Prevents excessive flower searching when none available

### Pollen Collection and Deposit Flow

1. **Flower Targeting**: Bees seek the nearest flower with pollen (state 4) using the cell-indexed cache
2. **Pollen Collection**: When close to flower (5px), collect pollen and enter scatter mode
3. **Scatter**: Bees wander briefly after collection to disperse
4. **Beehive Targeting**: Bees carrying pollen target the cached beehive entity
5. **Deposit**: When within 30 pixels of beehive, pollen is deposited
6. **Honey Conversion**: Deposited pollen is converted to honey (multiplied by beehive factor, prestige and night factors)

### Configuration Values (Current)

```zig
const POLLINATION_CHECK_INTERVAL = 0.5;  // Check pollination twice per second
const SEARCH_COOLDOWN = 0.3;             // Cooldown between flower searches
const MAX_AVAILABLE_FLOWERS = 256;       // Max flowers in per-frame cache
const ARRIVAL_THRESHOLD = 5.0;           // Distance for flower arrival
const BEEHIVE_ARRIVAL_THRESHOLD = 30.0;  // Distance for beehive arrival
const LEAP_FACTOR = 2.0;                 // Movement interpolation speed
const SCATTER_TIME_MIN = 2.0;            // Minimum scatter duration
const SCATTER_TIME_MAX = 4.0;            // Maximum scatter duration
const LIFESPAN_MIN = 60.0;               // Minimum bee lifespan (seconds)
const LIFESPAN_MAX = 140.0;              // Maximum bee lifespan (seconds)
```

---

## Legacy OOP Implementation (Removed)

The sections below describe the old `bee.zig` implementation that was removed during the ECS refactor. Kept for historical reference.

### Core Properties

```zig
pub const Bee = struct {
    // Positioning
    position: rl.Vector2,
    
    // Visual properties
    texture: rl.Texture,
    width: f32,           // 32 pixels
    height: f32,          // 32 pixels
    scale: f32,           // Base scale (1.0)
    effectiveScale: f32,  // Adjusted for grid zoom
    
    // AI and targeting
    targetFlowerIndex: ?usize,
    targetLock: bool,
    
    // Lifecycle
    timeAlive: f32,
    timeSpan: f32,        // 30-70 seconds lifespan
    dead: bool,
    
    // Gameplay mechanics
    carryingPollen: bool,
    pollenCollected: f32,
    
    // Development
    debug: bool,
}
```

## Bee Lifecycle

### Initialization

New bees are created with:
- Random position within grid bounds
- Random lifespan between 30-70 seconds
- No pollen collected initially
- Target acquisition disabled initially

### Aging and Death

Bees follow a simple aging system:
- `timeAlive` increases each frame by `deltaTime`
- When `timeAlive` exceeds `timeSpan`, bee dies
- Dead bees are removed from the game during cleanup

## AI Behavior System

### State Machine

The bee AI operates on a simple state machine:

1. **Target Acquisition** - When `targetLock` is false
2. **Movement** - When `targetLock` is true and target exists
3. **Pollen Collection** - When arriving at a flower with pollen
4. **Target Release** - When arriving at any flower

### Target Acquisition Algorithm

The `findNearestFlower` function implements a sophisticated targeting system:

**Phase 1: Priority Search**
- Scans all flowers for mature ones (state 4) with pollen
- Calculates distance to each viable flower
- Records the minimum distance found

**Phase 2: Randomization**
- Collects all flowers within 125% of minimum distance
- This creates a "close enough" group to prevent all bees targeting the same flower
- Randomly selects from this group

**Phase 3: Fallback**
- If no flowers with pollen exist, targets any living flower
- Ensures bees don't become idle when no pollen is available

### Movement System

**Leap Factor Movement:**
- Uses interpolation for smooth movement: `position += (target - position) * leapFactor * deltaTime`
- Leap factor of 0.9 creates natural, organic movement
- Accounts for frame rate variations through `deltaTime`

**Arrival Detection:**
- Arrival threshold of 5.0 pixels for reliable detection
- Prevents oscillation around target positions

## Pollen Collection Mechanics

### Collection Rules

Bees can collect pollen when:
- Target flower is mature (state == 4)
- Target flower has pollen (`hasPolen == true`)
- Bee is within arrival threshold of flower

### Collection Effects

When pollen is collected:
1. Flower's pollen is consumed (`flower.collectPolen()`)
2. Bee state changes to carrying pollen
3. Pollen counter increments by 1
4. Target lock is released for new target acquisition

## Honey Production

### Conversion System

- Each pollen collected equals 1 honey unit
- Honey is tracked in the main game loop
- Production occurs during the update phase

### Production Tracking

The game engine monitors:
- Previous pollen count before update
- Current pollen count after update
- Difference is added to global honey reserves

## Visual Representation

### Rendering System

**Normal State:**
- Renders bee texture with white tint
- Uses `effectiveScale` for proper grid scaling

**Pollen Carrying State:**
- Renders bee texture with yellow tint
- Provides immediate visual feedback

### Scale Management

The `updateScale` function ensures bees:
- Scale properly with grid zoom changes
- Maintain consistent appearance ratio
- Formula: `effectiveScale = scale * (gridScale / 3.0)`

## Flower Spawning Behavior

### Spawning Mechanics

Bees carrying pollen can spawn new flowers:
- 10% chance per second while carrying pollen
- Spawning occurs at the bee's current position
- Pollen is consumed when spawning succeeds

### Spawning Logic

The spawning system:
1. Converts bee world position to grid coordinates
2. Checks for existing flowers at the target position
3. Revives dead flowers or creates new ones
4. Resets bee's pollen carrying state

## Performance Considerations

### Optimization Features

**Efficient Target Finding:**
- Uses squared distance for initial comparisons (faster than sqrt)
- Only calculates actual distance when needed
- Limits search to living flowers only

**Memory Management:**
- Uses page allocator for temporary collections
- Properly cleans up dynamic arrays
- Minimal memory allocation per frame

### Scalability

The system can handle multiple bees efficiently:
- O(n*m) complexity where n = bees, m = flowers
- Reasonable performance for typical game scales
- Could be optimized with spatial partitioning if needed

## Configuration Values

```zig
const ARRIVAL_THRESHOLD = 5.0;      // Distance for arrival detection
const LEAP_FACTOR = 0.9;            // Movement interpolation speed
const DISTANCE_TOLERANCE = 1.25;    // Randomization factor for targeting
const LIFESPAN_MIN = 30.0;          // Minimum bee lifespan (seconds)
const LIFESPAN_MAX = 70.0;          // Maximum bee lifespan (seconds)
const SPRITE_SIZE = 32.0;           // Bee sprite dimensions
```

## Future Improvements

### Planned Features

1. **Bee Types** - Different bee species with unique abilities
2. **Swarm Intelligence** - Bees communicate about flower locations
3. **Pathfinding** - Navigate around obstacles
4. **Seasonal Behavior** - Different behavior patterns over time
5. **Bee Upgrades** - Longer lifespan, faster movement, more pollen capacity

### AI Enhancements

1. **Flocking Behavior** - Bees influence each other's movement
2. **Memory System** - Remember recently visited flowers
3. **Efficiency Optimization** - Prefer closer flowers more strongly
4. **Predictive Targeting** - Target flowers likely to have pollen soon

### Technical Improvements

1. **Spatial Partitioning** - Optimize flower searching with quadtree
2. **Behavior Trees** - More complex AI decision making
3. **Animation System** - Smooth sprite animation for movement
4. **Sound Integration** - Buzzing sounds and audio feedback

## API Reference

### Core Functions

```zig
pub fn init(x: f32, y: f32, texture: rl.Texture) Bee
pub fn update(self: *Bee, deltaTime: f32, flowers: []Flower, gridOffset: rl.Vector2, gridScale: f32) void
pub fn draw(self: Bee) void
pub fn updateScale(self: *Bee, gridScale: f32) void
pub fn enableDebug(self: *Bee) void
```

### Internal Functions

```zig
pub fn findNearestFlower(self: Bee, flowers: []Flower, gridOffset: rl.Vector2, gridScale: f32) ?usize
```

## Debugging Features

### Debug Mode

When `debug` is enabled:
- Additional visual indicators could be added
- Debug information could be displayed
- Currently used for development tracking

### Development Tools

Future debug features could include:
- Bee target lines
- AI state visualization
- Performance metrics
- Behavior analysis tools
