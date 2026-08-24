const std = @import("std");
const World = @import("../world.zig").World;

/// Fertile Soil node: multiplies flower maturation and pollen-regen speed.
pub var growthMul: f32 = 1.0;
pub const GROWTH_MUL_PER_LEVEL: f32 = 1.2;

pub fn growthMulForLevel(level: u16) f32 {
    return std.math.pow(f32, GROWTH_MUL_PER_LEVEL, @floatFromInt(level));
}

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

            if (growth.isRotten) continue;

            if (growth.state == 4) {
                if (!growth.hasPollen) {
                    growth.timeAlive += growth.growthRate * growthMul * deltaTime;
                    if (growth.timeAlive > growth.pollenCooldown) {
                        growth.hasPollen = true;
                        growth.timeAlive = 0;
                    }
                }
                continue;
            }

            if (growth.state < 4) {
                growth.timeAlive += growth.growthRate * growthMul * deltaTime;
                if (growth.timeAlive > growth.growthThreshold) {
                    growth.timeAlive = 0;
                    growth.state += 1;
                }
            }
        }
    }
}
