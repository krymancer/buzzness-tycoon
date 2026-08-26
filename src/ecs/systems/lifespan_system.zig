const rl = @import("raylib");
const std = @import("std");
const World = @import("../world.zig").World;
const components = @import("../components.zig");

/// Chance a mature flower withers in place instead of vanishing when its
/// lifespan ends. Rotten flowers block the cell until the player clears them.
pub const ROT_CHANCE_PERCENT: i32 = 60;

/// Live rot chance; lowered by the Hardy Blooms tree node.
pub var rotChancePercent: i32 = ROT_CHANCE_PERCENT;
/// Multiplicative per-level decay so the infinite repeatable always helps.
pub const ROT_CHANCE_DECAY_PER_LEVEL: f32 = 0.85;

pub fn rotChanceForLevel(level: u16) i32 {
    const chance = @as(f32, @floatFromInt(ROT_CHANCE_PERCENT)) *
        std.math.pow(f32, ROT_CHANCE_DECAY_PER_LEVEL, @floatFromInt(level));
    return @intFromFloat(@round(chance));
}

/// Age the flowers. (Bees age in bees.Store.age, and only when mortal.)
pub fn update(world: *World, deltaTime: f32) !void {
    var iter = world.iterateLifespans();

    while (iter.next()) |entity| {
        if (world.getLifespan(entity)) |lifespan| {
            lifespan.timeAlive += deltaTime;
            lifespan.totalTimeAlive += deltaTime;

            if (lifespan.isDead()) {
                // Dying FLOWER: immature ones get more time; mature ones
                // either wither in place (rot) or are cleared.
                if (world.getFlowerGrowth(entity)) |growth| {
                    if (growth.state < 4) {
                        lifespan.timeAlive = 0;
                        lifespan.totalTimeAlive = lifespan.timeSpan * 0.5; // Reset to halfway
                        continue;
                    }
                    if (!growth.isRotten and rl.getRandomValue(1, 100) <= rotChancePercent) {
                        rotFlower(world, entity, growth, lifespan);
                        continue;
                    }
                    try removeFlower(world, entity);
                    continue;
                }

                try world.destroyEntity(entity);
            }
        }
    }
}

/// Wither a mature flower in place: no pollen, no further aging, cell stays
/// occupied. Cleared by the player (see game.zig) via removeFlower.
pub fn rotFlower(world: *World, entity: u32, growth: *components.FlowerGrowth, lifespan: *components.Lifespan) void {
    growth.isRotten = true;
    growth.hasPollen = false;
    // Park the lifespan so isDead() stays false forever.
    lifespan.timeAlive = 0;
    lifespan.totalTimeAlive = 0;
    lifespan.timeSpan = std.math.floatMax(f32);
    world.clearFlowerTargetCount(entity);
}

/// Fully remove a flower: bee targets, grid registry (all 4 cells for a
/// SUPER flower) and the entity itself.
pub fn removeFlower(world: *World, entity: u32) !void {
    world.clearFlowerTargetCount(entity);
    if (world.getFlowerGrowth(entity)) |growth| {
        if (world.getGridPosition(entity)) |gridPos| {
            const gridX: i32 = @intFromFloat(@floor(gridPos.x));
            const gridY: i32 = @intFromFloat(@floor(gridPos.y));
            world.unregisterFlowerAtGrid(gridX, gridY);
            if (growth.isSuper) {
                world.unregisterFlowerAtGrid(gridX + 1, gridY);
                world.unregisterFlowerAtGrid(gridX, gridY + 1);
                world.unregisterFlowerAtGrid(gridX + 1, gridY + 1);
            }
        }
    }
    try world.destroyEntity(entity);
}
