# UI System

## Overview

The UI system (`ui.zig`) provides the game's user interface using **raygui** for interactive elements and Raylib for text rendering. It displays resource information and interactive buttons, styled with the Catppuccin Mocha theme.

## UI Structure

### Core Components

```zig
pub const UI = struct {
    // Currently stateless - state managed elsewhere
    // Theme applied during init()
}
```

### Design Philosophy

**Immediate Mode UI with raygui:**
- UI elements rendered fresh each frame
- Buttons managed by raygui library
- Catppuccin Mocha theme applied at initialization
- Clean separation between UI rendering and game logic

## Current UI Elements

### Resource Display

**Honey Counter:**
- Displays current honey amount
- Format: "Honey: [amount]"
- Position: Top-left corner (10, 10)
- Font size: 30 pixels
- Color: White

**Bee Counter:**
- Shows current bee population
- Format: "Bees: [count]"
- Position: Below honey counter (10, 40)
- Font size: 30 pixels
- Color: White

**Beehive Factor:**
- Shows current honey conversion multiplier
- Format: "Beehive Factor: [x]x"
- Position: Below bee counter (10, 70)
- Font size: 20 pixels
- Color: Yellow

### Interactive Elements (raygui)

**Buy Bee Button:**
- raygui button with Catppuccin styling
- Size: 220x40 pixels
- Position: (10, 100)
- Text: "Buy Bee (10 Honey)"
- Cost: 10 honey per bee
- Disabled state when insufficient honey

**Upgrade Beehive Button:**
- raygui button with Catppuccin styling
- Size: 220x40 pixels
- Position: (10, 150)
- Text: "Upgrade Beehive ([cost])"
- Cost doubles with each upgrade (starts at 20)
- Disabled state when insufficient honey

## UI Rendering System

### Draw Function

```zig
pub fn draw(self: UI, honey: f32, bees: usize, beehiveFactor: f32, upgradeCost: f32) struct { buyBee: bool, upgradeBeehive: bool }
```

**Parameters:**
- `honey`: Current honey amount to display
- `bees`: Current bee count to display
- `beehiveFactor`: Current honey conversion multiplier
- `upgradeCost`: Current beehive upgrade cost

**Returns:**
- `buyBee`: true if bee purchase button was clicked and affordable
- `upgradeBeehive`: true if upgrade button was clicked and affordable

### Button Implementation (raygui)

```zig
const buyBeeRect = rl.Rectangle.init(10, 100, buttonWidth, buttonHeight);
const canAffordBee = honey >= 10.0;

if (!canAffordBee) {
    rg.setState(@intFromEnum(rg.State.disabled));
}

const buyBeePressed = rg.button(buyBeeRect, "Buy Bee (10 Honey)");

if (!canAffordBee) {
    rg.setState(@intFromEnum(rg.State.normal));
}
```

## User Experience Design

### Visual Feedback

**Affordability Indicators:**
- Button color changes based on resource availability
- Immediate visual feedback for player decisions
- Clear distinction between available and disabled states

**Real-time Updates:**
- Resource counters update immediately
- Button states change as resources fluctuate
- No lag between game state and UI display

### Accessibility

**Clear Typography:**
- Large, readable font sizes
- High contrast white text on dark background
- Consistent text positioning

**Intuitive Interactions:**
- Standard mouse click interactions
- Visual hover states could be added
- Consistent button behavior

## Integration with Game Systems

### Resource System Integration

**Resource Display:**
- Direct access to honey and bee count
- Real-time resource tracking
- No caching or state management needed

**Transaction Handling:**
- UI requests purchases, game validates
- Clean separation of concerns
- UI doesn't directly modify resources

### Game Loop Integration

**Update Cycle:**
```zig
// In game draw loop
if (self.ui.draw(self.resources.honey, self.bees.items.len)) {
    if (self.resources.spendHoney(10.0)) {
        // Create new bee
        var bee = Bee.init(randomPos.x, randomPos.y, self.textures.bee);
        bee.updateScale(self.grid.scale);
        try self.bees.append(bee);
    }
}
```

## Performance Considerations

### Optimization Features

**Minimal Processing:**
- Simple text and rectangle drawing
- No complex UI calculations
- Efficient immediate mode rendering

**No State Management:**
- No UI state to update or maintain
- No memory allocations for UI elements
- Clean, stateless design

### Scalability

**Easy Extension:**
- Simple function-based approach
- Easy to add new UI elements
- Modular design for complex interfaces

## Configuration Values

```zig
const HONEY_DISPLAY_POS = (10, 10);      // Honey counter position
const BEE_DISPLAY_POS = (10, 40);        // Bee counter position
const BUTTON_POS = (10, 80);             // Button position
const BUTTON_SIZE = (220, 40);           // Button dimensions
const FONT_SIZE_LARGE = 30;              // Resource display font size
const FONT_SIZE_MEDIUM = 20;             // Button text font size
const BEE_COST = 10.0;                   // Cost displayed on button
```

## Future Improvements

### Planned Features

1. **Additional Resources** - Display more resource types
2. **Multiple Buttons** - More purchase options
3. **Tooltips** - Hover information for UI elements
4. **Animations** - Smooth transitions and effects
5. **Notifications** - Popup messages for game events

### Enhanced Interactions

1. **Keyboard Shortcuts** - Hotkeys for common actions
2. **Button Hover Effects** - Visual feedback for mouse-over
3. **Sound Effects** - Audio feedback for UI interactions
4. **Confirmation Dialogs** - Prevent accidental purchases
5. **Progress Bars** - Visual progress indicators

### Advanced UI Features

1. **Menus and Panels** - More complex UI layouts
2. **Settings Panel** - Game configuration options
3. **Statistics Display** - Detailed game metrics
4. **Achievement System** - Progress and milestone tracking
5. **Help System** - In-game tutorials and hints

## Technical Improvements

### Planned Enhancements

1. **UI State Management** - Track UI element states
2. **Layout System** - Flexible UI positioning
3. **Theme System** - Customizable UI appearance
4. **Input Handling** - More sophisticated input processing
5. **Accessibility Features** - Screen reader support, high contrast modes

### Performance Optimizations

1. **Draw Call Batching** - Reduce rendering overhead
2. **Texture Atlas** - Efficient UI texture management
3. **Clipping** - Only draw visible UI elements
4. **Caching** - Cache expensive UI calculations
5. **Profiling** - Monitor UI performance

## API Reference

### Core Functions

```zig
pub fn init() UI
pub fn deinit(self: UI) void
pub fn draw(self: UI, honey: f32, bees: usize) bool
```

### Usage Examples

```zig
// Initialize UI
var ui = UI.init();

// In game loop
const purchaseRequested = ui.draw(resources.honey, bees.items.len);
if (purchaseRequested) {
    if (resources.spendHoney(10.0)) {
        // Create new bee
    }
}

// Cleanup
ui.deinit();
```

## Debugging Features

### Debug Information

Potential debug features:
- UI element bounds visualization
- Mouse position display
- Button state indicators
- Performance metrics

### Development Tools

Future debug tools could include:
- UI layout editor
- Interactive element inspector
- Performance profiler
- Accessibility checker

## Error Handling

### Input Validation

**Safe Interactions:**
- Validates resource availability before purchases
- Prevents invalid transactions
- Graceful handling of edge cases

**Bounds Checking:**
- Mouse position validation
- Safe rectangle collision detection
- Proper text rendering bounds

## Styling and Theming

### Catppuccin Mocha Theme

The UI uses the Catppuccin Mocha dark theme, applied via `theme.zig`:

```zig
pub fn init() UI {
    theme.applyCatppuccinMochaTheme();
    return .{};
}
```

**Color Scheme:**
- Background: Dark theme (0x1e, 0x1e, 0x2e)
- Text: White for readability
- Accent: Yellow for important info (beehive factor)
- Buttons: Styled by raygui with theme colors

### Future Theming

**Customizable Themes:**
- Color palette system
- Font customization
- Layout variations
- Animation preferences

## Integration Examples

### Game Engine Integration

```zig
// In game draw function
if (self.ui.draw(self.resources.honey, self.bees.items.len)) {
    if (self.resources.spendHoney(10.0)) {
        const randomPos = self.grid.getRandomPositionInBounds();
        var bee = Bee.init(randomPos.x, randomPos.y, self.textures.bee);
        bee.updateScale(self.grid.scale);
        try self.bees.append(bee);
    }
}
```

### Resource System Integration

```zig
// UI checks resource availability
const canAfford = honey >= 10.0;
const buttonColor = if (canAfford) rl.Color.yellow else rl.Color.gray;

// Transaction handling
if (mouseClicked and canAfford) {
    return true;  // Request purchase
}
```

This UI system provides a solid foundation for player interaction while maintaining simplicity and extensibility for future development.
