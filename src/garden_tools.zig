//! Flower removal clears the occupied footprint and its plans together.
const std = @import("std");
const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");
const meadow_plan = @import("meadow_plan.zig");
const lifespan = @import("ecs/systems/lifespan_system.zig");

/// Returns whether a flower was removed. Empty cells still lose their plan.
/// SUPER flowers are one entity: touching any of their four cells clears all
/// four plans. The hive and positions outside the meadow are never touched.
pub fn removeAt(world: *World, width: usize, height: usize, x: i32, y: i32) !bool {
    if (width == 0 or height == 0 or x < 0 or y < 0 or x >= width or y >= height) return false;
    if (x == (width - 1) / 2 and y == (height - 1) / 2) return false;
    const entity = world.getFlowerAtGrid(x, y) orelse {
        meadow_plan.set(x, y, null);
        return false;
    };
    const growth = world.getFlowerGrowth(entity) orelse return false;
    const pos = world.getGridPosition(entity) orelse return false;
    const ax: i32 = @intFromFloat(@floor(pos.x));
    const ay: i32 = @intFromFloat(@floor(pos.y));
    const span: usize = if (growth.isSuper) 2 else 1;
    try lifespan.removeFlower(world, entity);
    // Finish before the next lifespan/AI update can visit the removed entity.
    try world.processDestroyQueue();
    for (0..span) |dy| {
        for (0..span) |dx| meadow_plan.set(ax + @as(i32, @intCast(dx)), ay + @as(i32, @intCast(dy)), null);
    }
    return true;
}

test "removal clears live and rotten flowers, plans, and target claims without touching the hive" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    meadow_plan.reset();
    defer meadow_plan.reset();
    for ([_]bool{ false, true }, 0..) |rotten, i| {
        const x: i32 = @intCast(i + 2);
        const entity = try world.createEntity();
        try world.addGridPosition(entity, components.GridPosition.init(@floatFromInt(x), 3));
        var growth = components.FlowerGrowth.init(.rose);
        growth.isRotten = rotten;
        try world.addFlowerGrowth(entity, growth);
        world.registerFlowerAtGrid(x, 3, entity);
        try world.flowerTargetCount.put(entity, 2);
        meadow_plan.set(x, 3, .rose);
        try std.testing.expect(try removeAt(&world, 17, 17, x, 3));
        try std.testing.expect(!world.hasFlowerAtGrid(x, 3));
        try std.testing.expectEqual(@as(u32, 0), world.getFlowerTargetCount(entity));
        try std.testing.expect(meadow_plan.get(x, 3) == null);
        try std.testing.expect(!try removeAt(&world, 17, 17, x, 3));
        try world.processDestroyQueue();
        try std.testing.expect(world.getFlowerGrowth(entity) == null);
    }
    meadow_plan.set(8, 8, .rose);
    try std.testing.expect(!try removeAt(&world, 17, 17, 8, 8));
    try std.testing.expect(meadow_plan.get(8, 8) != null);
    try std.testing.expect(!try removeAt(&world, 17, 17, -1, 3));
    try std.testing.expect(!try removeAt(&world, 17, 17, 17, 3));
    meadow_plan.set(4, 4, .iris);
    try std.testing.expect(!try removeAt(&world, 17, 17, 4, 4));
    try std.testing.expect(meadow_plan.get(4, 4) == null);
}

test "touching a SUPER flower corner clears its whole footprint exactly once" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    meadow_plan.reset();
    defer meadow_plan.reset();
    const entity = try world.createEntity();
    try world.addGridPosition(entity, components.GridPosition.init(3, 3));
    var growth = components.FlowerGrowth.init(.tulip);
    growth.isSuper = true;
    try world.addFlowerGrowth(entity, growth);
    for (3..5) |y| {
        for (3..5) |x| {
            world.registerFlowerAtGrid(@intCast(x), @intCast(y), entity);
            meadow_plan.set(@intCast(x), @intCast(y), .tulip);
        }
    }
    try std.testing.expect(try removeAt(&world, 17, 17, 4, 4));
    try std.testing.expectEqual(@as(usize, 0), meadow_plan.count());
    for (3..5) |y| {
        for (3..5) |x| try std.testing.expect(!world.hasFlowerAtGrid(@intCast(x), @intCast(y)));
    }
    try std.testing.expect(!try removeAt(&world, 17, 17, 3, 3));
    try std.testing.expectEqual(@as(usize, 0), world.entitiesToDestroy.items.len);
    try std.testing.expect(world.getFlowerGrowth(entity) == null);
    try world.processDestroyQueue();
}
