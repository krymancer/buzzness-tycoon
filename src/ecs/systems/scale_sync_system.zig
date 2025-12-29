const World = @import("../world.zig").World;

// Cache last grid scale to detect changes
var lastGridScale: f32 = 0;
var forceNextUpdate: bool = true;

pub fn update(world: *World, gridScale: f32) void {
    // Skip if grid scale hasn't changed and we don't need a forced update
    // (First frame or after new entities are added)
    const scaleChanged = gridScale != lastGridScale;

    if (!scaleChanged and !forceNextUpdate) {
        return;
    }

    lastGridScale = gridScale;
    forceNextUpdate = false;

    var iter = world.iterateScaleSyncs();

    while (iter.next()) |entity| {
        if (world.getScaleSync(entity)) |scaleSync| {
            if (world.getSprite(entity)) |sprite| {
                scaleSync.updateFromGrid(sprite.scale, gridScale);
            }
        }
    }
}

/// Call this when new entities with ScaleSync are added
pub fn markDirty() void {
    forceNextUpdate = true;
}
