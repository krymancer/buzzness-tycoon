const rl = @import("raylib");
const std = @import("std");
const World = @import("../world.zig").World;
const components = @import("../components.zig");

/// Chance a mature flower withers in place instead of vanishing when its
/// lifespan ends. Rotten flowers block the cell until the player clears them.
pub const ROT_CHANCE_PERCENT: i32 = 60;

const config = @import("../../config.zig");

pub fn update(world: *World, deltaTime: f32) !void {
    var iter = world.iterateLifespans();

    while (iter.next()) |entity| {
        if (world.getLifespan(entity)) |lifespan| {
            lifespan.timeAlive += deltaTime;
            lifespan.totalTimeAlive += deltaTime;

            if (lifespan.isDead()) {
                if (config.bees_immortal and world.getBeeAI(entity) != null) {
                    lifespan.timeAlive = 0;
                    lifespan.totalTimeAlive = 0;
                    continue;
                }

                // Cleanup for dying BEE: decrement flower target count
                if (world.getBeeAI(entity)) |beeAI| {
                    if (beeAI.targetLocked and beeAI.targetEntity != null) {
                        // Only decrement if targeting a flower (not beehive).
                        // Beehive targets don't need cleanup since they're never added
                        // to flowerTargetCount - only flowers are tracked there.
                        // Note: If the flower was already destroyed, getFlowerGrowth returns null
                        // and we skip decrement, which is correct since the flower's death
                        // already cleared its entry via clearFlowerTargetCount.
                        if (world.getFlowerGrowth(beeAI.targetEntity.?) != null) {
                            world.decrementFlowerTarget(beeAI.targetEntity.?);
                        }
                    }

                    // Check if this is a bee carrying pollen - if so, extend life instead of dying
                    if (beeAI.carryingPollen) {
                        // Extend lifespan by 50%
                        const extension = lifespan.timeSpan * 0.5;
                        lifespan.timeSpan += extension;
                        lifespan.timeAlive = 0; // Reset time alive
                        beeAI.carryingPollen = false; // Consume the pollen

                        // Also reset the pollen collected
                        if (world.getPollenCollector(entity)) |collector| {
                            collector.pollenCollected = 0;
                        }
                        continue; // Don't destroy this entity
                    }
                }

                // Dying FLOWER: immature ones get more time; mature ones
                // either wither in place (rot) or are cleared.
                if (world.getFlowerGrowth(entity)) |growth| {
                    if (growth.state < 4) {
                        lifespan.timeAlive = 0;
                        lifespan.totalTimeAlive = lifespan.timeSpan * 0.5; // Reset to halfway
                        continue;
                    }
                    if (!growth.isRotten and rl.getRandomValue(1, 100) <= ROT_CHANCE_PERCENT) {
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
