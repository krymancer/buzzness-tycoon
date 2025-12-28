# Game Engine System

## Overview

The game engine (`game.zig`) serves as the central orchestrator for Buzzness Tycoon, managing the main game loop and ECS (Entity Component System) coordination. It follows a data-oriented architecture with distinct initialization, update, and render phases.

## ECS Architecture

The game uses an **Entity Component System** architecture:

- **Entities**: Simple u32 IDs managed by `World`
- **Components**: Pure data structures (Position, BeeAI, FlowerGrowth, etc.)
- **Systems**: Pure functions that operate on components
- **World**: Central storage and query system

See [ECS Refactor Plan](./ecs-refactor-plan.md) for complete architecture details.

## Architecture

### Core Components

```zig
pub const Game = struct {
    // Grid configuration
    const GRID_WIDTH = 17;
    const GRID_HEIGHT = 17;
    const FLOWER_SPAWN_CHANCE = 30;
    
    // Core systems
    grid: Grid,
    textures: Textures,
    resources: Resources,
    ui: UI,
    metrics: Metrics,
    
    // ECS World
    world: World,
    
    // Camera system
    cameraOffset: rl.Vector2,
    isDragging: bool,
    lastMousePos: rl.Vector2,
    
    // Beehive upgrades
    beehiveUpgradeCost: f32,
    cachedBeeCount: usize,
    cachedFlowerCount: usize,
    
    // Window management
    width: f32,
    height: f32,
    windowIcon: rl.Image,
    
    allocator: std.mem.Allocator,
}
```

## Game Loop

### Initialization (`init`)

The initialization phase sets up:

1. **Window Creation** - Creates fullscreen window with dynamic resolution
2. **Random Seed** - Initializes random number generator for gameplay variety
3. **System Initialization** - Sets up grid, textures, resources, and UI
4. **ECS World Creation** - Initializes entity component storage
5. **Entity Spawning** - Creates initial flowers (30% per cell) and bees (10 initial bees)

**Initial Flower Spawning:**
- Iterates through all 17x17 grid positions
- 30% chance per tile to spawn a flower
- Randomly selects flower type (rose, dandelion, tulip)
- Creates entity with: GridPosition, Sprite, FlowerGrowth, Lifespan components
- Flowers start at growth state 0, mature to state 4
- Center position (8, 8) reserved for beehive

**Beehive Spawning:**
- Single beehive entity spawned at grid center (8, 8)
- Creates entity with: GridPosition, Sprite, Beehive components
- Serves as the pollen deposit point for honey conversion

**Initial Bee Spawning:**
- Spawns 100 bees at random positions within grid bounds
- Creates entity with: Position, Sprite, BeeAI, Lifespan, PollenCollector, ScaleSync components
- Bees have 60-140 second initial lifespan
- Bee AI initialized with random wander angle

### Update Phase (`update`)

The update phase runs ECS systems in this order:

1. **Lifespan System**
   - Ages all entities (bees and flowers)
   - Checks for death conditions
   - Extends bee life if carrying pollen (+50% lifespan)
   - Queues dead entities for destruction

2. **Flower Growth System**
   - Progresses flower growth states (0 → 4)
   - Regenerates pollen for mature flowers (state 4)
   - Manages pollen cooldown timers

3. **Bee AI System**
   - Handles pollination (10% chance to spawn flower when flying over empty cells)
   - Manages scatter behavior (2-4 seconds after collecting pollen)
   - When carrying pollen, targets beehive for deposit
   - Deposits pollen at beehive when within 30 pixels
   - Finds nearest flower with density limiting (max 2 bees per flower)
   - Random walk when no targets available
   - Bee movement toward targets

4. **Flower Spawning System**
   - Every 5 seconds, checks random empty cells
   - 30% chance to spawn flower in empty cells
   - Ensures sustainable flower population

5. **Scale Sync System**
   - Synchronizes entity scales with grid zoom level

6. **Honey Conversion**
   - Checks all bees for completed pollen deposits
   - Converts pollen to honey when `!carryingPollen && pollenCollected > 0`
   - Honey amount multiplied by beehive's `honeyConversionFactor`
   - Resets pollen counter after conversion

7. **Entity Cleanup**
   - Processes destroy queue to remove dead entities

8. **Metrics Logging**
   - Logs FPS, frame time, bee count, and flower count
   - Outputs to console when performance drops or periodically

### Render Phase (`draw`)

The render phase uses the render system:

1. **Background** - Clears screen with dark theme color (Catppuccin Mocha base)
2. **Grid** - Renders isometric grid tiles
3. **Render System** - Draws all entities with sprites:
   - Flowers at grid positions with growth-based colors
   - Bees at world positions with yellow tint when carrying pollen
   - Frustum culling skips off-screen bees
4. **UI** - Displays honey counter, bee count, beehive factor, purchase buttons (raygui)
5. **Debug Info** - Shows FPS counter and frame time in milliseconds

## ECS Systems

### System Execution Order

```zig
try lifespan_system.update(&self.world, deltaTime);
try flower_growth_system.update(&self.world, deltaTime);
try bee_ai_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
try flower_spawning_system.update(&self.world, deltaTime, self.grid.offset, self.grid.scale, GRID_WIDTH, GRID_HEIGHT, self.textures);
try scale_sync_system.update(&self.world, self.grid.scale);
```

### Component Queries

The World provides query methods and direct iterators:
- `iterateBees()` - Fast, allocation-free bee iteration
- `iterateFlowers()` - Fast, allocation-free flower iteration
- `getFlowerTargetCount(entity)` - O(1) bee density check
- `hasFlowerAtGrid(x, y)` - O(1) spatial flower lookup

## Input System

### Camera Controls

The game supports intuitive camera controls:

**Mouse Dragging:**
- Left mouse button initiates drag mode
- Mouse movement translates the camera offset
- Updates both camera and grid offsets simultaneously

**Zoom Control:**
- Mouse wheel controls zoom level
- Zoom range: 1.0x to 6.0x
- Automatically updates bee scales to match grid zoom

**Keyboard Shortcuts:**
- Alt + Enter: Toggle fullscreen mode

## Entity Management

### Bee Management

The game maintains a dynamic list of bees with the following lifecycle:

1. **Spawning** - New bees are created via UI button (costs 10 honey)
2. **Living** - Bees collect pollen and produce honey
3. **Dying** - Bees die after 30-70 seconds of life
4. **Cleanup** - Dead bees are removed from the array

### Flower Management

Flowers follow a more complex lifecycle:

1. **Initial Spawn** - 30% chance during world generation
2. **Growth** - Flowers progress through 5 states (0-4)
3. **Pollen Production** - Mature flowers (state 4) produce pollen
4. **Death** - Flowers die after 60-120 seconds
5. **Revival** - Dead flowers can be revived by pollen-carrying bees

## Rendering System

### Isometric Rendering

The game uses a centralized rendering approach:

**Grid-Based Rendering:**
```zig
pub fn drawSpriteAtGridPosition(texture, i, j, sourceRect, scale, color)
```
- Converts grid coordinates to screen position
- Centers sprites on isometric tiles
- Applies proper scaling based on grid zoom

**World-Based Rendering:**
```zig
pub fn drawSpriteAtWorldPosition(texture, worldPos, sourceRect, scale, color)
```
- Renders sprites at absolute world positions
- Used for dynamic entities like bees

### Visual Effects

**Pollen Glow Effect:**
- Mature flowers with pollen display a yellow glow
- Implemented by drawing the flower twice with different colors
- Creates visual feedback for pollen availability

**Bee Pollen Indicator:**
- Bees carrying pollen are tinted yellow
- Provides clear visual feedback for bee state

## Memory Management

The game uses careful memory management:

- **Allocator-Based** - Uses provided allocator for dynamic arrays
- **Proper Cleanup** - All resources are freed in `deinit()`
- **Texture Management** - Textures are loaded once and reused
- **Entity Cleanup** - Dead entities are removed to prevent memory leaks

## Configuration Constants

```zig
const GRID_WIDTH = 17;           // Grid width in tiles (odd for center)
const GRID_HEIGHT = 17;          // Grid height in tiles (odd for center)
const FLOWER_SPAWN_CHANCE = 30;  // Percentage chance for initial flower spawn
const INITIAL_BEE_COUNT = 100;   // Number of bees spawned at start
const BEE_COST = 10.0;           // Honey cost per bee purchase
const INITIAL_UPGRADE_COST = 20.0; // First beehive upgrade cost
```

## Future Improvements

### Planned Features

1. **Game Over Conditions** - Implement proper lose state when all bees die
2. **Save System** - Persist game state between sessions
3. **Audio System** - Add sound effects and music
4. **More Upgrades** - Additional beehive and bee upgrades

### Technical Debt

1. **Configuration System** - Move magic numbers to configuration files
2. **Error Handling** - Improve error propagation and handling

## API Reference

### Core Functions

```zig
pub fn init(width: f32, height: f32, allocator: std.mem.Allocator) !Game
pub fn deinit(self: Game) void
pub fn run(self: *Game) !void
pub fn input(self: *Game) void
pub fn update(self: *Game) !void
pub fn draw(self: *Game) !void
```

### Utility Functions

```zig
pub fn drawSpriteAtGridPosition(self: *Game, texture, i, j, sourceRect, scale, color) void
pub fn drawSpriteAtWorldPosition(self: *Game, texture, worldPos, sourceRect, scale, color) void
pub fn trySpawnFlower(self: *Game, beePosition: rl.Vector2) !bool
```
