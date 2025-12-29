const World = @import("../world.zig").World;

pub fn update(world: *World, deltaTime: f32) !void {
    // Use direct iterator - no allocation
    var iter = world.iterateFlowers();

    while (iter.next()) |entity| {
        if (world.getFlowerGrowth(entity)) |growth| {
            if (world.getLifespan(entity)) |lifespan| {
                if (lifespan.isDead()) {
                    continue;
                }
            }

            if (growth.state == 4) {
                if (!growth.hasPollen) {
                    growth.timeAlive += growth.growthRate * deltaTime;
                    if (growth.timeAlive > growth.pollenCooldown) {
                        growth.hasPollen = true;
                        growth.timeAlive = 0;
                    }
                }
                continue;
            }

            if (growth.state < 4) {
                growth.timeAlive += growth.growthRate * deltaTime;
                if (growth.timeAlive > growth.growthThreshold) {
                    growth.timeAlive = 0;
                    growth.state += 1;
                }
            }
        }
    }
}
