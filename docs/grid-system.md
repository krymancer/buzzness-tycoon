# Grid System

## Overview

The Grid system (`grid.zig`) provides the foundation for the isometric game world. It manages the visual representation of the game field, handles coordinate transformations, and provides camera functionality through zoom and offset controls.

## Grid Structure

### Core Properties

```zig
pub const Grid = struct {
    // Dimensions
    width: usize,            // Grid width in tiles (17)
    height: usize,           // Grid height in tiles (17)
    
    // Tile properties
    tileTexture: rl.Texture, // Grass cube texture
    tileWidth: f32,          // Tile width in pixels (32)
    tileHeight: f32,         // Tile height in pixels (32)
    
    // Camera system
    offset: rl.Vector2,      // Camera offset for positioning
    scale: f32,              // Current zoom level
    baseScale: f32,          // Default zoom level (3.0)
    minScale: f32,           // Minimum zoom (1.0)
    maxScale: f32,           // Maximum zoom (6.0)
    
    // Viewport
    viewportWidth: f32,      // Screen width
    viewportHeight: f32,     // Screen height
    
    // Development
    debug: bool,             // Debug mode toggle
}
```

## Isometric Coordinate System

### Coordinate Spaces

The grid system manages three coordinate spaces:

1. **Grid Coordinates** - Integer tile positions (0,0 to width-1, height-1)
2. **World Coordinates** - Floating-point pixel positions in isometric space
3. **Screen Coordinates** - Final pixel positions on screen

### Coordinate Transformation

The system uses utility functions for coordinate conversion:

**Grid to World:**
```zig
utils.isoToXY(gridX, gridY, tileWidth, tileHeight, offset.x, offset.y, scale)
```

**World to Grid:**
```zig
utils.xyToIso(worldX, worldY, tileWidth, tileHeight, offset.x, offset.y, scale)
```

## Camera System

### Offset Management

**Centering Algorithm:**
- `calculateCenteredGridOffset` centers the grid in the viewport
- Calculates bounding box of isometric grid
- Centers this box within the screen dimensions
- Accounts for tile size and current zoom level

**Dynamic Offset Updates:**
- Camera dragging modifies offset directly
- Zoom changes trigger offset recalculation
- Maintains grid centering at different zoom levels

### Zoom System

**Zoom Controls:**
- Mouse wheel controls zoom level
- Zoom range: 1.0x to 6.0x
- Smooth zoom transitions

**Zoom Effects:**
- Affects tile rendering size
- Triggers entity scale updates
- Maintains grid centering
- Updates effective coordinates

## Rendering System

### Tile Rendering

**Isometric Tile Placement:**
- Iterates through all grid positions
- Converts grid coordinates to screen positions
- Renders tiles using current scale and offset

**Rendering Loop:**
```zig
for (0..self.width) |i| {
    for (0..self.height) |j| {
        const position = utils.isoToXY(i, j, tileWidth, tileHeight, offset.x, offset.y, scale);
        rl.drawTextureEx(tileTexture, position, 0, scale, color);
    }
}
```

### Visual Features

**Mouse Hover Detection:**
- `isMouseHovering` function detects mouse over tiles
- Uses point-in-isometric-tile algorithm
- Highlights hovered tiles in debug mode

**Debug Visualization:**
- Hovered tiles render in red
- Normal tiles render in white
- Debug mode can be toggled on/off

## Utility Functions

### Position Conversion

**Grid to World Position:**
- Converts integer grid coordinates to world position
- Accounts for tile size, offset, and scale
- Returns center position of tile

**Random Position Generation:**
```zig
pub fn getRandomPositionInBounds(self: Grid) rl.Vector2
```
- Generates random position within grid bounds
- Adds random offset within tile for variety
- Used for bee spawning and placement

### Boundary Management

**Grid Bounds:**
- Width and height define playable area
- Coordinate validation prevents out-of-bounds access
- Boundary checks for entity placement

## Interactive Features

### Mouse Interaction

**Hover Detection:**
- Real-time mouse position tracking
- Isometric tile hit detection
- Visual feedback for hovered tiles

**Click Handling:**
- Could be extended for tile selection
- Foundation for future interactive features
- Coordinate conversion for world interaction

### Camera Controls

**Drag Controls:**
- Mouse drag to pan camera
- Immediate visual feedback
- Smooth camera movement

**Zoom Controls:**
- Mouse wheel zoom
- Constrained zoom range
- Maintains grid centering

## Performance Considerations

### Optimization Features

**Efficient Rendering:**
- Simple nested loop for tile rendering
- Minimal coordinate calculations per tile
- Texture reuse for all tiles

**Memory Management:**
- Single texture for all tiles
- No dynamic allocations during rendering
- Efficient coordinate transformations

### Scalability

**Grid Size:**
- Current 17x17 grid (289 tiles)
- Odd dimensions ensure center tile for beehive
- Could be expanded for larger worlds
- Performance scales linearly with grid size

## Configuration Values

```zig
const GRID_WIDTH = 17;          // Default grid width (odd for center)
const GRID_HEIGHT = 17;         // Default grid height (odd for center)
const TILE_WIDTH = 32.0;        // Tile width in pixels
const TILE_HEIGHT = 32.0;       // Tile height in pixels
const BASE_SCALE = 3.0;         // Default zoom level
const MIN_SCALE = 1.0;          // Minimum zoom
const MAX_SCALE = 6.0;          // Maximum zoom
```

## Future Improvements

### Planned Features

1. **Tile Variations** - Different tile types and textures
2. **Terrain Heights** - Multi-level isometric terrain
3. **Tile Properties** - Walkable/unwalkable tiles
4. **Grid Overlays** - Visual grid lines and indicators
5. **Infinite Scrolling** - Larger world with viewport culling

### Enhanced Interaction

1. **Tile Selection** - Click to select tiles
2. **Tile Information** - Hover tooltips and details
3. **Building System** - Place structures on tiles
4. **Terrain Editor** - Runtime tile modification
5. **Pathfinding Integration** - Navigation mesh generation

### Technical Improvements

1. **Viewport Culling** - Only render visible tiles
2. **Level of Detail** - Different detail levels at different zooms
3. **Texture Atlasing** - Efficient texture management
4. **Instanced Rendering** - GPU-optimized tile rendering
5. **Lighting System** - Dynamic lighting and shadows

## API Reference

### Core Functions

```zig
pub fn init(width: usize, height: usize, viewportWidth: f32, viewportHeight: f32) !Grid
pub fn deinit(self: Grid) void
pub fn draw(self: Grid) void
pub fn zoom(self: *Grid, zoomDelta: f32) void
pub fn updateOffset(self: *Grid) void
pub fn enableDebug(self: *Grid) void
```

### Utility Functions

```zig
pub fn getRandomPositionInBounds(self: Grid) rl.Vector2
pub fn isMouseHovering(self: Grid, x: f32, y: f32) bool
```

### Integration Functions

```zig
// Used by other systems for coordinate conversion
utils.isoToXY(x, y, tileWidth, tileHeight, offset.x, offset.y, scale)
utils.xyToIso(x, y, tileWidth, tileHeight, offset.x, offset.y, scale)
utils.calculateCenteredGridOffset(width, height, tileWidth, tileHeight, scale, viewportWidth, viewportHeight)
```

## Debugging Features

### Debug Mode

When `debug` is enabled:
- Hovered tiles highlight in red
- Grid coordinate information could be displayed
- Tile boundaries could be visualized

### Development Tools

Future debug features could include:
- Grid coordinate overlay
- Tile property visualization
- Performance metrics display
- Camera information panel
- Zoom level indicators

## Integration with Other Systems

### Entity Positioning

**Flower Placement:**
- Flowers use grid coordinates for positioning
- Grid provides world position calculation
- Handles scale and offset transformations

**Bee Movement:**
- Bees use world coordinates for movement
- Grid provides coordinate conversion utilities
- Handles boundary checking and positioning

### Camera Integration

**Unified Camera System:**
- Grid offset affects all entity rendering
- Zoom level scales all visual elements
- Consistent coordinate system across all systems
