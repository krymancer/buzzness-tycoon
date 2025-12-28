const World = @import("../world.zig").World;

pub fn update(world: *World, deltaTime: f32) !void {
    var iter = world.iterateLifespans();

    while (iter.next()) |entity| {
        if (world.getLifespan(entity)) |lifespan| {
            lifespan.timeAlive += deltaTime;
            lifespan.totalTimeAlive += deltaTime;

            if (lifespan.isDead()) {
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

                // Cleanup for dying FLOWER: clear its target count entry and unregister from grid
                if (world.getFlowerGrowth(entity) != null) {
                    world.clearFlowerTargetCount(entity);

                    // Unregister flower from spatial lookup
                    if (world.getGridPosition(entity)) |gridPos| {
                        const gridX: i32 = @intFromFloat(@floor(gridPos.x));
                        const gridY: i32 = @intFromFloat(@floor(gridPos.y));
                        world.unregisterFlowerAtGrid(gridX, gridY);
                    }
                }

                try world.destroyEntity(entity);
            }
        }
    }
}
