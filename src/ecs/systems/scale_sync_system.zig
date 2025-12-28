const World = @import("../world.zig").World;

pub fn update(world: *World, gridScale: f32) void {
    var iter = world.iterateScaleSyncs();

    while (iter.next()) |entity| {
        if (world.getScaleSync(entity)) |scaleSync| {
            if (world.getSprite(entity)) |sprite| {
                scaleSync.updateFromGrid(sprite.scale, gridScale);
            }
        }
    }
}
