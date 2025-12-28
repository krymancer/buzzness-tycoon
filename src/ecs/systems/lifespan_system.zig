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
                        // Only decrement if targeting a flower (not beehive)
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

                // Cleanup for dying FLOWER: clear its target count entry
                if (world.getFlowerGrowth(entity) != null) {
                    world.clearFlowerTargetCount(entity);
                }

                try world.destroyEntity(entity);
            }
        }
    }
}
