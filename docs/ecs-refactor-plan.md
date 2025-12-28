# ECS Architecture Documentation

> **✅ REFACTOR COMPLETED**  
> This document describes the completed ECS migration. The game now runs on a full Entity Component System architecture with performance optimizations.

## Overview

Successfully migrated from traditional object-oriented architecture to Entity Component System (ECS) to support advanced features like:
- ✅ Bee scatter behavior and density limiting
- ✅ Pollination mechanics (bees spawn flowers)
- ✅ Automatic flower spawning in empty cells
- ✅ Pollen-based life extension for bees
- ✅ Dynamic honey generation with beehive upgrades
- ✅ Performance optimizations for 1000+ bees (48-53 FPS)
- ✅ Metrics and performance logging system
- Future: Boost totems, new entity types, status effects

## Previous Architecture (Removed)

- ~~`Bee` and `Flower` structs with data + methods~~ (deleted)
- ~~`Game` holds `ArrayList(Bee)` and `ArrayList(Flower)`~~
- ~~Each entity updates itself (`bee.update()`, `flower.update()`)~~
- ~~Manual iteration and index tracking for dead entities~~

## Current ECS Architecture

### Entities
Unique IDs (`u32`) managed by `EntityManager` with free list recycling.

```zig
// src/ecs/entity.zig
pub const Entity = u32;
```

### Components (Pure Data)

Located in `src/ecs/components.zig`:

#### Core Components
```zig
Position { 
    x: f32, 
    y: f32 
}

GridPosition { 
    x: f32, 
    y: f32 
}

Sprite { 
    texture: rl.Texture, 
    width: f32, 
    height: f32, 
    scale: f32 
}

Velocity { 
    x: f32, 
    y: f32 
}
```

#### Behavior Components
```zig
BeeAI { 
    targetEntity: ?Entity,
    targetLocked: bool,
    carryingPollen: bool,
    wanderAngle: f32,
    wanderChangeTimer: f32,
    lastGridX: i32,
    lastGridY: i32,
    scatterTimer: f32,
    searchCooldown: f32,     // Cooldown between flower searches
}

FlowerGrowth {
    state: f32,
    timeAlive: f32,
    growthRate: f32,
    growthThreshold: f32,
    hasPollen: bool,
    pollenCooldown: f32,
}

Lifespan {
    timeAlive: f32,
    totalTimeAlive: f32,
    timeSpan: f32,
}

PollenCollector { 
    pollenCollected: f32 
}

ScaleSync { 
    effectiveScale: f32 
}

Beehive { 
    honeyConversionFactor: f32,  // Multiplier for honey generation (upgradeable)
}
```

### Systems (Pure Logic)

All systems implemented in `src/ecs/systems/`:

1. **LifespanSystem** ✅ - Tracks entity age, marks entities as dead, handles pollen life extension
2. **FlowerGrowthSystem** ✅ - Updates flower growth states (0→4), handles pollen regeneration
3. **BeeAISystem** ✅ - Target finding with density limiting, movement, scatter behavior, pollination
   - Optimized with per-frame flower caching
   - Cached beehive entity and position
   - O(1) flower target count lookups
4. **FlowerSpawningSystem** ✅ - Spawns flowers in empty cells every 5 seconds (30% chance)
5. **ScaleSyncSystem** ✅ - Updates entity scales based on grid zoom level
6. **RenderSystem** ✅ - Draws all entities with Position/GridPosition + Sprite components
   - Includes frustum culling for off-screen bees

### World Structure

```zig
World {
    allocator: Allocator,
    entityManager: EntityManager,
    
    // Component storage (ArrayLists for each component type)
    positions: ArrayList(Position),
    gridPositions: ArrayList(GridPosition),
    sprites: ArrayList(Sprite),
    velocities: ArrayList(Velocity),
    beeAIs: ArrayList(BeeAI),
    flowerGrowths: ArrayList(FlowerGrowth),
    lifespans: ArrayList(Lifespan),
    pollenCollectors: ArrayList(PollenCollector),
    scaleSync: ArrayList(ScaleSync),
    beehives: ArrayList(Beehive),
    
    // Sparse mapping: entityId -> component array index
    entityToPosition: AutoHashMap(Entity, usize),
    entityToGridPosition: AutoHashMap(Entity, usize),
    entityToSprite: AutoHashMap(Entity, usize),
    entityToVelocity: AutoHashMap(Entity, usize),
    entityToBeeAI: AutoHashMap(Entity, usize),
    entityToFlowerGrowth: AutoHashMap(Entity, usize),
    entityToLifespan: AutoHashMap(Entity, usize),
    entityToPollenCollector: AutoHashMap(Entity, usize),
    entityToScaleSync: AutoHashMap(Entity, usize),
    entityToBeehive: AutoHashMap(Entity, usize),
    
    // Performance optimization: O(1) flower lookups
    flowerTargetCount: AutoHashMap(Entity, usize),  // Bees targeting each flower
    gridPosToFlower: AutoHashMap(u64, Entity),      // Grid position to flower entity
    
    // Destroy queue for deferred entity removal
    entitiesToDestroy: ArrayList(Entity),
}
```

## Implementation Status

### Phase 1: Core ECS Infrastructure ✅
**Status**: COMPLETED

- ✅ Create `src/ecs/` directory structure
- ✅ Implement `entity.zig` - Entity ID type with free list recycling
- ✅ Implement `components.zig` - All 9 component struct definitions
- ✅ Implement `world.zig` - Component storage with add/remove/get methods
- ✅ Implement query system for component iteration (6 query methods)

**Files created**:
- `src/ecs/entity.zig`
- `src/ecs/components.zig`
- `src/ecs/world.zig`

### Phase 2: Component Migration ✅
**Status**: COMPLETED

- ✅ Position data from Bee/Flower
- ✅ GridPosition for grid-based entities
- ✅ Sprite/rendering data
- ✅ BeeAI behavior data (with scatter, pollination tracking)
- ✅ FlowerGrowth behavior data
- ✅ Lifespan/death tracking data
- ✅ PollenCollector stats
- ✅ ScaleSync for grid zoom
- ✅ Velocity component

**Files modified**:
- `src/ecs/components.zig` (all components defined)

### Phase 3: System Implementation ✅
**Status**: COMPLETED

- ✅ Create `src/ecs/systems/` directory
- ✅ Implement `lifespan_system.zig` (with pollen life extension)
- ✅ Implement `flower_growth_system.zig`
- ✅ Implement `bee_ai_system.zig` (with scatter, density limiting, pollination)
- ✅ Implement `flower_spawning_system.zig` (empty cell spawning)
- ✅ Implement `scale_sync_system.zig`
- ✅ Implement `render_system.zig`

**Files created**:
- `src/ecs/systems/lifespan_system.zig`
- `src/ecs/systems/flower_growth_system.zig`
- `src/ecs/systems/bee_ai_system.zig`
- `src/ecs/systems/flower_spawning_system.zig`
- `src/ecs/systems/scale_sync_system.zig`
- `src/ecs/systems/render_system.zig`

### Phase 4: Game Integration ✅
**Status**: COMPLETED

- ✅ Add World to `Game` struct
- ✅ Migrate entity spawning (10 bees, 30% flowers per cell)
- ✅ Replace `update()` method with system execution
- ✅ Replace `draw()` method with render system
- ✅ Honey conversion from pollen collection
- ✅ Bee purchasing with ECS entity creation
- [ ] Remove old `ArrayList(Bee)` and `ArrayList(Flower)`
- [ ] Remove or archive old `bee.zig` and `flower.zig`

**Files to modify**:
- `src/game.zig` (major refactor)

**Files to potentially archive**:
- `src/bee.zig` (keep for reference during migration)
- `src/flower.zig` (keep for reference during migration)

### Phase 5: Testing & Verification
**Goal**: Ensure everything works as before

- [ ] Verify bees spawn and move correctly
- [ ] Verify flowers grow and produce pollen
- [ ] Verify pollen collection works
- [ ] Verify flower spawning from bees works
- [ ] Verify entities die after timespan
- [ ] Verify dead entity cleanup works
- [ ] Verify rendering matches old behavior
- [ ] Verify camera/zoom interactions work
- [ ] Verify resource counting (honey) works
- [ ] Performance testing

## Benefits of ECS

✅ **Better cache coherence** - Components stored in contiguous arrays  
✅ **Easier extensibility** - Add boost totems by adding components  
✅ **Cleaner separation** - Data completely separate from logic  
✅ **Parallelization potential** - Systems can run independently  
✅ **Simplified entity management** - One cleanup system handles all dead entities  
✅ **Better for serialization** - Save/load is just dumping component arrays  
✅ **More testable** - Systems are pure functions operating on data

## Future Features Enabled by ECS

### Boost Totems
```zig
BoostEffect { 
    radius: f32, 
    multiplier: f32, 
    affectType: BoostType 
}
```
System queries all entities near totems and applies multipliers.

### New Entity Types
- **Predators**: Add `Predator` + `Velocity` components
- **Buildings**: Add `Structure` + `GridPosition` components
- **Workers**: Add `WorkerAI` + `Inventory` components

### Advanced Behaviors
- **Flocking**: Query nearby bees, apply separation/alignment/cohesion
### Phase 5: Code Cleanup ✅
**Status**: COMPLETED

- ✅ Remove old `src/bee.zig`
- ✅ Remove old `src/flower.zig`
- ✅ Remove unused `src/eventEmmiter.zig`
- ✅ Clean up unused theme functions
- ✅ Remove unused Grid methods
- ✅ Clean up Resources struct
- ✅ Update documentation

**Files removed**:
- `src/bee.zig`
- `src/flower.zig`
- `src/eventEmmiter.zig`

## New Gameplay Mechanics (ECS-Enabled)

### Bee Scatter Behavior
- After collecting pollen, bees scatter for 2-4 seconds
- Prevents immediate re-targeting of nearest flower
- Creates more organic movement patterns
- Spreads bees across the map

### Bee Density Limiting
- Maximum of 2 bees can target the same flower
- Checks both active targets and proximity (100px radius)
- Prevents clustering around single flowers
- Encourages even distribution

### Pollination Mechanics
- Bees carrying pollen have 10% chance to spawn flowers when flying over empty cells
- Tracks last grid position to avoid duplicate spawns
- Creates organic flower spreading
- Player-influenced map expansion

### Automatic Flower Spawning
- Every 5 seconds, checks 5 random grid cells
- 30% chance to spawn flower in empty cells
- Ensures sustainable flower population
- Prevents game from running out of resources

### Pollen Life Extension
- Bees carrying pollen when lifespan ends get +50% lifespan extension
- Pollen is consumed (no honey generated)
- Resets timeAlive counter
- Rewards productive bees

### Honey Deposit System
- Bees carry pollen for 3 seconds before depositing
- Deposit converts pollen to honey (1:1 ratio)
- Visual indicator (yellow tint) when carrying pollen
- Creates strategic timing gameplay

## Benefits of ECS Architecture

✅ **Performance**: Better cache locality, data-oriented design  
✅ **Scalability**: Easy to add new component types and entities  
✅ **Flexibility**: Mix and match components without inheritance  
✅ **Maintainability**: Pure data and pure logic separation  
✅ **Testability**: Systems can be tested independently  
✅ **Future-Ready**: Foundation for complex mechanics (boost totems, status effects, etc.)

## Future Expansion Ideas

### Boost Totem System
- **BoostEffect Component**: `{ type: BoostType, range: f32, multiplier: f32 }`
- **BoostType Enum**: HoneyMultiplier, SpeedBoost, LifespanExtension, FlowerGrowth
- **Totem Entity**: GridPosition + BoostEffect + Sprite
- **System**: Checks bees in range, applies effects

### Status Effect System
- **StatusEffect Component**: `{ effectType: EffectType, duration: f32, strength: f32 }`
- **EffectType Enum**: Poison, Speed, Invulnerability, DoubleHoney
- **System**: Updates durations, applies/removes effects

### Predator System
- **Predator Component**: `{ targetEntity: ?Entity, aggression: f32 }`
- **Entities**: Birds, wasps that chase bees
- **System**: Find nearest bee, chase, reduce bee lifespan on contact

## Migration Strategy

~~1. **Incremental**: Build ECS alongside existing code~~  
~~2. **Parallel Testing**: Run both systems simultaneously to verify parity~~  
~~3. **Gradual Cutover**: Switch one entity type at a time~~  
~~4. **Rollback Safety**: Keep old code until ECS is fully verified~~

**✅ Migration Complete**: Full cutover to ECS architecture successful

## System Execution Order

### Update Phase
```
LifespanSystem (checks pollen life extension)
   ↓
FlowerGrowthSystem (progresses growth states)
   ↓
BeeAISystem (pollination, scatter, targeting, movement)
   ↓
FlowerSpawningSystem (empty cell spawning)
   ↓
ScaleSyncSystem (grid zoom sync)
   ↓
Honey Conversion (pollen → honey when deposited)
   ↓
Entity Cleanup (process destroy queue)
```

### Render Phase
```
Grid Rendering
   ↓
RenderSystem (draws all entities with sprites)
   ↓
UI Layer (honey counter, bee count, purchase button)
```

## Performance Characteristics

- **Entity Creation**: O(1) with free list recycling
- **Component Add/Remove**: O(1) hash map operations
- **Component Lookup**: O(1) sparse mapping
- **System Iteration**: O(n) where n = entities with matching components
- **Memory**: Sparse mapping overhead, but cache-friendly component arrays

## Notes & Considerations

✅ Textures/resources separate from ECS (shared assets)  
✅ Sparse mapping for O(1) component lookup by entity ID  
✅ Destroy queue for safe deferred entity removal  
✅ Grid reference passed to systems, not stored per entity  
✅ Camera offset as global state, not per entity  
✅ Zig 0.15 compatibility (ArrayList.empty, allocator parameters)

## Timeline

- Phase 1-2: Completed in 1 day (ECS core + components)
- Phase 3: Completed in 2 days (all systems)
- Phase 4: Completed in 1 day (game integration)
- Phase 5: Completed in 1 day (cleanup + docs)
- **Total**: 5 days for full migration ✅

## References

- Current `bee.zig` implementation (for behavior extraction)
- Current `flower.zig` implementation (for behavior extraction)
- Current `game.zig` update/draw loops (for system design)
