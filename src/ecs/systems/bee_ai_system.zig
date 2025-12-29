const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const Entity = @import("../entity.zig").Entity;
const components = @import("../components.zig");
const textures = @import("../../textures.zig");
const Textures = textures.Textures;
const Flowers = textures.Flowers;
const utils = @import("../../utils.zig");

var pollinationTimer: f32 = 0;
const POLLINATION_CHECK_INTERVAL: f32 = 0.5;
const SEARCH_COOLDOWN: f32 = 0.3;
const MOVEMENT_LEAP_FACTOR: f32 = 2.0;

// Cached beehive entity and position - only lookup once
// NOTE: This cache is never invalidated. The beehive is permanent and never destroyed.
var cachedBeehiveEntity: ?Entity = null;
var cachedBeehiveWorldPos: ?rl.Vector2 = null;
var beehiveCacheInitialized: bool = false;

// Cached available flowers - rebuilt once per frame
// NOTE: Fixed size array limits to 256 flowers, sufficient for current gameplay.
const MAX_AVAILABLE_FLOWERS: usize = 256;
var availableFlowers: [MAX_AVAILABLE_FLOWERS]AvailableFlower = undefined;
var availableFlowerCount: usize = 0;

const AvailableFlower = struct {
    entity: Entity,
    worldPos: rl.Vector2,
};

pub fn update(world: *World, deltaTime: f32, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize, texturesRef: Textures) !void {
    pollinationTimer += deltaTime;
    const checkPollination = pollinationTimer >= POLLINATION_CHECK_INTERVAL;
    if (checkPollination) {
        pollinationTimer = 0;
    }

    if (!beehiveCacheInitialized) {
        cachedBeehiveEntity = findBeehive(world);
        if (cachedBeehiveEntity) |beehiveEntity| {
            if (world.getGridPosition(beehiveEntity)) |gridPos| {
                cachedBeehiveWorldPos = getFlowerWorldPosition(gridPos.toVector2(), gridOffset, gridScale);
            }
        }
        beehiveCacheInitialized = true;
    }

    buildAvailableFlowersCache(world, gridOffset, gridScale);

    var iter = world.iterateBees();
    while (iter.next()) |entity| {
        if (world.getBeeAI(entity)) |beeAI| {
            if (world.getPosition(entity)) |position| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) continue;
                }

                if (beeAI.searchCooldown > 0) {
                    beeAI.searchCooldown -= deltaTime;
                }

                if (beeAI.scatterTimer > 0) {
                    beeAI.scatterTimer -= deltaTime;
                    performRandomWalk(beeAI, position, deltaTime);
                    continue;
                }

                if (checkPollination and beeAI.carryingPollen) {
                    try handlePollination(world, beeAI, position, gridOffset, gridScale, gridWidth, gridHeight, texturesRef);
                }

                if (beeAI.carryingPollen) {
                    if (!beeAI.targetLocked) {
                        beeAI.targetEntity = cachedBeehiveEntity;
                        if (beeAI.targetEntity != null) {
                            beeAI.targetLocked = true;
                        }
                    }

                    if (cachedBeehiveWorldPos) |targetPos| {
                        const distance = rl.math.vector2Distance(position.toVector2(), targetPos);
                        if (distance < 30.0) {
                            if (world.getPollenCollector(entity)) |collector| {
                                if (collector.pollenCollected > 0) {
                                    beeAI.carryingPollen = false;
                                    beeAI.targetLocked = false;
                                    beeAI.targetEntity = null;
                                }
                            }
                        } else {
                            moveTowards(position, targetPos, deltaTime);
                        }
                    }
                    continue;
                }

                if (!beeAI.targetLocked) {
                    if (beeAI.searchCooldown <= 0) {
                        beeAI.targetEntity = findNearestFlowerFromCache(world, position.toVector2());
                        if (beeAI.targetEntity != null) {
                            beeAI.targetLocked = true;
                            world.incrementFlowerTarget(beeAI.targetEntity.?);
                        } else {
                            beeAI.searchCooldown = SEARCH_COOLDOWN;
                        }
                    }

                    if (!beeAI.targetLocked) {
                        performRandomWalk(beeAI, position, deltaTime);
                    }
                } else {
                    if (beeAI.targetEntity) |targetEntity| {
                        if (world.getGridPosition(targetEntity)) |targetGridPos| {
                            if (world.getFlowerGrowth(targetEntity)) |targetFlower| {
                                const targetPos = getFlowerWorldPosition(targetGridPos.toVector2(), gridOffset, gridScale);
                                const distance = rl.math.vector2Distance(position.toVector2(), targetPos);

                                if (distance < 5.0) {
                                    if (targetFlower.state == 4 and targetFlower.hasPollen) {
                                        targetFlower.hasPollen = false;
                                        beeAI.carryingPollen = true;

                                        if (world.getPollenCollector(entity)) |collector| {
                                            collector.collect(1.0 * targetFlower.pollenMultiplier);
                                        }

                                        beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(20, 40))) / 10.0;
                                    }

                                    world.decrementFlowerTarget(targetEntity);
                                    beeAI.targetLocked = false;
                                    beeAI.targetEntity = null;
                                } else {
                                    moveTowards(position, targetPos, deltaTime);
                                }
                            } else {
                                world.decrementFlowerTarget(targetEntity);
                                beeAI.targetLocked = false;
                                beeAI.targetEntity = null;
                            }
                        } else {
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

fn moveTowards(position: anytype, target: rl.Vector2, deltaTime: f32) void {
    position.x += (target.x - position.x) * MOVEMENT_LEAP_FACTOR * deltaTime;
    position.y += (target.y - position.y) * MOVEMENT_LEAP_FACTOR * deltaTime;
}

fn buildAvailableFlowersCache(world: *World, gridOffset: rl.Vector2, gridScale: f32) void {
    availableFlowerCount = 0;

    var iter = world.iterateFlowers();
    while (iter.next()) |entity| {
        if (availableFlowerCount >= MAX_AVAILABLE_FLOWERS) break;

        if (world.getFlowerGrowth(entity)) |growth| {
            if (growth.state != 4 or !growth.hasPollen) continue;

            const beesNearFlower = world.getFlowerTargetCount(entity);
            if (beesNearFlower >= 2) continue;

            if (world.getGridPosition(entity)) |gridPos| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) continue;
                }

                availableFlowers[availableFlowerCount] = .{
                    .entity = entity,
                    .worldPos = getFlowerWorldPosition(gridPos.toVector2(), gridOffset, gridScale),
                };
                availableFlowerCount += 1;
            }
        }
    }
}

fn findNearestFlowerFromCache(world: *World, beePosition: rl.Vector2) ?Entity {
    var minimumDistanceSoFar = std.math.floatMax(f32);
    var nearestFlowerEntity: ?Entity = null;

    for (0..availableFlowerCount) |i| {
        const flower = availableFlowers[i];

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

    return rl.Vector2.init(
        tilePosition.x + (tileTotalWidth - flowerWidth * effectiveScale) / 2.0,
        tilePosition.y + (tileTotalHeight * 0.25) - (flowerHeight * effectiveScale),
    );
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

    position.x += @cos(beeAI.wanderAngle) * wanderSpeed * deltaTime;
    position.y += @sin(beeAI.wanderAngle) * wanderSpeed * deltaTime;
}

fn handlePollination(world: *World, beeAI: anytype, position: anytype, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize, texturesRef: Textures) !void {
    const gridPos = utils.worldToGrid(position.toVector2(), gridOffset, gridScale);
    const gridX: i32 = @intFromFloat(@floor(gridPos.x));
    const gridY: i32 = @intFromFloat(@floor(gridPos.y));

    if (gridX == beeAI.lastGridX and gridY == beeAI.lastGridY) return;

    beeAI.lastGridX = gridX;
    beeAI.lastGridY = gridY;

    if (gridX < 0 or gridY < 0 or gridX >= @as(i32, @intCast(gridWidth)) or gridY >= @as(i32, @intCast(gridHeight))) return;

    const centerX: i32 = @intCast((gridWidth - 1) / 2);
    const centerY: i32 = @intCast((gridHeight - 1) / 2);
    if (gridX == centerX and gridY == centerY) return;

    if (!world.hasFlowerAtGrid(gridX, gridY)) {
        if (rl.getRandomValue(1, 100) <= 10) {
            const flowerType = switch (rl.getRandomValue(1, 3)) {
                1 => Flowers.rose,
                2 => Flowers.dandelion,
                3 => Flowers.tulip,
                else => Flowers.rose,
            };

            const flowerTexture = texturesRef.getFlowerTexture(flowerType);
            const gridXf: f32 = @floatFromInt(gridX);
            const gridYf: f32 = @floatFromInt(gridY);

            const flowerEntity = try world.createEntity();
            try world.addGridPosition(flowerEntity, components.GridPosition.init(gridXf, gridYf));
            try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
            try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(textures.flowersToFlowerType(flowerType)));
            try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));
            world.registerFlowerAtGrid(gridX, gridY, flowerEntity);
        }
    }
}
