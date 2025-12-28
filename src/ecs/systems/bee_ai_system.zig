const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const Entity = @import("../entity.zig").Entity;
const components = @import("../components.zig");
const Textures = @import("../../textures.zig").Textures;
const Flowers = @import("../../textures.zig").Flowers;
const utils = @import("../../utils.zig");

var pollinationTimer: f32 = 0;
const POLLINATION_CHECK_INTERVAL: f32 = 0.5; // Only check pollination twice per second
const SEARCH_COOLDOWN: f32 = 0.3; // Reduced cooldown since search is now cheap

// Cached beehive entity - only lookup once
var cachedBeehiveEntity: ?Entity = null;
var beehiveCacheInitialized: bool = false;

// Cached available flowers - rebuilt once per frame
const MAX_AVAILABLE_FLOWERS: usize = 256;
var availableFlowers: [MAX_AVAILABLE_FLOWERS]AvailableFlower = undefined;
var availableFlowerCount: usize = 0;

const AvailableFlower = struct {
    entity: Entity,
    worldPos: rl.Vector2,
};

pub fn update(world: *World, deltaTime: f32, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize, textures: Textures) !void {
    // Update pollination timer
    pollinationTimer += deltaTime;
    const checkPollination = pollinationTimer >= POLLINATION_CHECK_INTERVAL;
    if (checkPollination) {
        pollinationTimer = 0;
    }

    // Cache beehive entity on first call
    if (!beehiveCacheInitialized) {
        cachedBeehiveEntity = findBeehive(world);
        beehiveCacheInitialized = true;
    }

    // Build available flowers cache ONCE per frame (instead of per-bee)
    buildAvailableFlowersCache(world, gridOffset, gridScale);

    var iter = world.iterateBees();
    while (iter.next()) |entity| {
        if (world.getBeeAI(entity)) |beeAI| {
            if (world.getPosition(entity)) |position| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) {
                        continue;
                    }
                }

                // Update search cooldown
                if (beeAI.searchCooldown > 0) {
                    beeAI.searchCooldown -= deltaTime;
                }

                // Handle scatter timer - force bees to wander after collecting pollen
                if (beeAI.scatterTimer > 0) {
                    beeAI.scatterTimer -= deltaTime;
                    performRandomWalk(beeAI, position, deltaTime);
                    continue; // Skip targeting while scattering
                }

                // Pollination mechanic: Only check periodically to reduce overhead
                if (checkPollination and beeAI.carryingPollen) {
                    try handlePollination(world, entity, beeAI, position, gridOffset, gridScale, gridWidth, gridHeight, textures);
                }

                // If carrying pollen, find and go to beehive
                if (beeAI.carryingPollen) {
                    if (!beeAI.targetLocked) {
                        beeAI.targetEntity = cachedBeehiveEntity;
                        if (beeAI.targetEntity != null) {
                            beeAI.targetLocked = true;
                        }
                    }

                    if (beeAI.targetEntity) |targetEntity| {
                        if (world.getGridPosition(targetEntity)) |targetGridPos| {
                            const targetPos = getFlowerWorldPosition(targetGridPos.toVector2(), gridOffset, gridScale);
                            const distance = rl.math.vector2Distance(position.toVector2(), targetPos);
                            const arrivalThreshold: f32 = 30.0;

                            if (distance < arrivalThreshold) {
                                // Deposit pollen at beehive
                                if (world.getPollenCollector(entity)) |collector| {
                                    if (collector.pollenCollected > 0) {
                                        beeAI.carryingPollen = false;
                                        beeAI.targetLocked = false;
                                        beeAI.targetEntity = null;
                                    }
                                }
                            } else {
                                // Move towards beehive
                                const leapFactor: f32 = 2.0;
                                position.x += (targetPos.x - position.x) * leapFactor * deltaTime;
                                position.y += (targetPos.y - position.y) * leapFactor * deltaTime;
                            }
                        }
                    }
                    continue;
                }

                // Not carrying pollen - look for flowers
                if (!beeAI.targetLocked) {
                    // Only search if cooldown expired
                    if (beeAI.searchCooldown <= 0) {
                        // Use fast cached search instead of iterating all flowers
                        beeAI.targetEntity = findNearestFlowerFromCache(world, position.toVector2());
                        if (beeAI.targetEntity != null) {
                            beeAI.targetLocked = true;
                            world.incrementFlowerTarget(beeAI.targetEntity.?);
                        } else {
                            // No target found, set cooldown and wander
                            beeAI.searchCooldown = SEARCH_COOLDOWN;
                        }
                    }

                    // Wander while searching or on cooldown
                    if (!beeAI.targetLocked) {
                        performRandomWalk(beeAI, position, deltaTime);
                    }
                } else {
                    // Has a locked target - move towards it
                    if (beeAI.targetEntity) |targetEntity| {
                        if (world.getGridPosition(targetEntity)) |targetGridPos| {
                            if (world.getFlowerGrowth(targetEntity)) |targetFlower| {
                                const targetPos = getFlowerWorldPosition(targetGridPos.toVector2(), gridOffset, gridScale);
                                const distance = rl.math.vector2Distance(position.toVector2(), targetPos);
                                const arrivalThreshold: f32 = 5.0;

                                if (distance < arrivalThreshold) {
                                    if (targetFlower.state == 4 and targetFlower.hasPollen) {
                                        targetFlower.hasPollen = false;
                                        beeAI.carryingPollen = true;

                                        if (world.getPollenCollector(entity)) |collector| {
                                            collector.collect(1.0);
                                        }

                                        // Make bee scatter away from flower for 2-4 seconds
                                        beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(20, 40))) / 10.0;
                                    }

                                    // Decrement flower target count before unlocking
                                    world.decrementFlowerTarget(targetEntity);
                                    beeAI.targetLocked = false;
                                    beeAI.targetEntity = null;
                                } else {
                                    // Move towards flower
                                    const leapFactor: f32 = 2.0;
                                    position.x += (targetPos.x - position.x) * leapFactor * deltaTime;
                                    position.y += (targetPos.y - position.y) * leapFactor * deltaTime;
                                }
                            } else {
                                // Flower growth missing - unlock and search again
                                world.decrementFlowerTarget(targetEntity);
                                beeAI.targetLocked = false;
                                beeAI.targetEntity = null;
                            }
                        } else {
                            // Grid position missing - unlock and search again
                            world.decrementFlowerTarget(targetEntity);
                            beeAI.targetLocked = false;
                            beeAI.targetEntity = null;
                        }
                    } else {
                        performRandomWalk(beeAI, position, deltaTime);
                    }
                }
            }
        }
    }
}

// Build available flowers cache once per frame - O(flowers) instead of O(bees * flowers)
fn buildAvailableFlowersCache(world: *World, gridOffset: rl.Vector2, gridScale: f32) void {
    availableFlowerCount = 0;

    var iter = world.iterateFlowers();
    while (iter.next()) |entity| {
        if (availableFlowerCount >= MAX_AVAILABLE_FLOWERS) break;

        if (world.getFlowerGrowth(entity)) |growth| {
            // Only consider flowers with pollen ready
            if (growth.state != 4 or !growth.hasPollen) continue;

            // Check bee density using O(1) cached count
            const beesNearFlower = world.getFlowerTargetCount(entity);
            if (beesNearFlower >= 2) continue; // Skip overcrowded flowers

            if (world.getGridPosition(entity)) |gridPos| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) continue;
                }

                const worldPos = getFlowerWorldPosition(gridPos.toVector2(), gridOffset, gridScale);
                availableFlowers[availableFlowerCount] = .{
                    .entity = entity,
                    .worldPos = worldPos,
                };
                availableFlowerCount += 1;
            }
        }
    }
}

// Fast flower lookup using pre-built cache - O(cached flowers) instead of O(all flowers)
fn findNearestFlowerFromCache(world: *World, beePosition: rl.Vector2) ?Entity {
    var minimumDistanceSoFar = std.math.floatMax(f32);
    var nearestFlowerEntity: ?Entity = null;

    for (0..availableFlowerCount) |i| {
        const flower = availableFlowers[i];

        // Re-check overcrowding (may have changed since cache was built)
        const beesNearFlower = world.getFlowerTargetCount(flower.entity);
        if (beesNearFlower >= 2) continue;

        const distance = rl.math.vector2DistanceSqr(flower.worldPos, beePosition);
        if (distance < minimumDistanceSoFar) {
            minimumDistanceSoFar = distance;
            nearestFlowerEntity = flower.entity;
        }
    }

    return nearestFlowerEntity;
}

fn findBeehive(world: *World) ?Entity {
    var iter = world.entityToBeehive.keyIterator();
    if (iter.next()) |entity| {
        return entity.*;
    }
    return null;
}

fn getFlowerWorldPosition(gridPos: rl.Vector2, offset: rl.Vector2, gridScale: f32) rl.Vector2 {
    const tileWidth: f32 = 32;
    const tileHeight: f32 = 32;
    const flowerWidth: f32 = 32;
    const flowerHeight: f32 = 32;
    const flowerScale: f32 = 2;

    const tilePosition = utils.isoToXY(gridPos.x, gridPos.y, tileWidth, tileHeight, offset.x, offset.y, gridScale);
    const effectiveScale = flowerScale * (gridScale / 3.0);

    const tileTotalWidth = 32 * gridScale;
    const tileTotalHeight = 32 * gridScale;

    const centeredX = tilePosition.x + (tileTotalWidth - flowerWidth * effectiveScale) / 2.0;
    const centeredY = tilePosition.y + (tileTotalHeight * 0.25) - (flowerHeight * effectiveScale);

    return rl.Vector2.init(centeredX, centeredY);
}

fn performRandomWalk(beeAI: anytype, position: anytype, deltaTime: f32) void {
    const wanderSpeed: f32 = 50.0;
    const wanderChangeInterval: f32 = 1.0;

    beeAI.wanderChangeTimer += deltaTime;

    if (beeAI.wanderChangeTimer >= wanderChangeInterval) {
        const angleChange = @as(f32, @floatFromInt(rl.getRandomValue(-30, 30))) * std.math.pi / 180.0;
        beeAI.wanderAngle += angleChange;
        beeAI.wanderChangeTimer = 0;
    }

    const moveX = @cos(beeAI.wanderAngle) * wanderSpeed * deltaTime;
    const moveY = @sin(beeAI.wanderAngle) * wanderSpeed * deltaTime;

    position.x += moveX;
    position.y += moveY;
}

fn handlePollination(world: *World, _: Entity, beeAI: anytype, position: anytype, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize, textures: Textures) !void {
    // Convert bee's world position to grid coordinates
    const gridPos = utils.worldToGrid(position.toVector2(), gridOffset, gridScale);
    const gridX: i32 = @intFromFloat(@floor(gridPos.x));
    const gridY: i32 = @intFromFloat(@floor(gridPos.y));

    // Check if we've moved to a new grid cell
    if (gridX == beeAI.lastGridX and gridY == beeAI.lastGridY) {
        return; // Still in same cell, don't check again
    }

    // Update last grid position
    beeAI.lastGridX = gridX;
    beeAI.lastGridY = gridY;

    // Check if position is within grid bounds
    if (gridX < 0 or gridY < 0 or gridX >= @as(i32, @intCast(gridWidth)) or gridY >= @as(i32, @intCast(gridHeight))) {
        return;
    }

    // Skip beehive tile
    const centerX: i32 = @intCast((gridWidth - 1) / 2);
    const centerY: i32 = @intCast((gridHeight - 1) / 2);
    if (gridX == centerX and gridY == centerY) {
        return;
    }

    // Check if there's already a flower at this position
    const gridXf: f32 = @floatFromInt(gridX);
    const gridYf: f32 = @floatFromInt(gridY);

    var hasFlower = false;
    var flowerIter = world.iterateFlowers();

    while (flowerIter.next()) |flowerEntity| {
        if (world.getGridPosition(flowerEntity)) |flowerGridPos| {
            if (@abs(flowerGridPos.x - gridXf) < 0.1 and @abs(flowerGridPos.y - gridYf) < 0.1) {
                hasFlower = true;
                break;
            }
        }
    }

    // If no flower exists, 10% chance to spawn one
    if (!hasFlower) {
        const spawnChance = rl.getRandomValue(1, 100);
        if (spawnChance <= 10) {
            // Spawn a random flower type
            const flowerTypeRoll = rl.getRandomValue(1, 3);
            const flowerType = switch (flowerTypeRoll) {
                1 => Flowers.rose,
                2 => Flowers.dandelion,
                3 => Flowers.tulip,
                else => Flowers.rose,
            };

            const flowerTexture = textures.getFlowerTexture(flowerType);

            const flowerEntity = try world.createEntity();
            try world.addGridPosition(flowerEntity, components.GridPosition.init(gridXf, gridYf));
            try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
            try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init());
            try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));
        }
    }
}
