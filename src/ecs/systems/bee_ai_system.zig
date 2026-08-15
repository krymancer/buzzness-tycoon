const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const Entity = @import("../entity.zig").Entity;
const components = @import("../components.zig");
const textures = @import("../../textures.zig");
const Textures = textures.Textures;
const Flowers = textures.Flowers;
const utils = @import("../../utils.zig");
const Resources = @import("../../resources.zig").Resources;
const labs_mod = @import("../../labs.zig");
const prestige_mod = @import("../../prestige.zig");

var pollinationTimer: f32 = 0;
const POLLINATION_CHECK_INTERVAL: f32 = 0.5;
const SEARCH_COOLDOWN: f32 = 0.3;
const MOVEMENT_LEAP_FACTOR: f32 = 2.0;

const STAGGER_GROUPS: usize = 4;
var currentStaggerGroup: usize = 0;

var cachedBeehiveEntity: ?Entity = null;
var cachedBeehiveGridX: f32 = 0;
var cachedBeehiveGridY: f32 = 0;
var beehiveCacheInitialized: bool = false;

const MAX_AVAILABLE_FLOWERS: usize = 512;
var availableFlowers: [MAX_AVAILABLE_FLOWERS]AvailableFlower = undefined;
var availableFlowerCount: usize = 0;

const AvailableFlower = struct {
    entity: Entity,
    gridX: f32,
    gridY: f32,
};

pub const UpdateCtx = struct {
    world: *World,
    deltaTime: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    gridWidth: usize,
    gridHeight: usize,
    texturesRef: Textures,
    resources: *Resources,
    labs: *const labs_mod.LabState,
    prestige: *prestige_mod.PrestigeState,
    honeyFactor: f32,
    frameHoneyGain: *f32,
};

pub fn resetCaches() void {
    cachedBeehiveEntity = null;
    beehiveCacheInitialized = false;
    availableFlowerCount = 0;
    currentStaggerGroup = 0;
    pollinationTimer = 0;
}

pub fn update(ctx: UpdateCtx) !void {
    const scaledDeltaTime = ctx.deltaTime * @as(f32, @floatFromInt(STAGGER_GROUPS));

    pollinationTimer += ctx.deltaTime;
    const checkPollination = pollinationTimer >= POLLINATION_CHECK_INTERVAL;
    if (checkPollination) pollinationTimer = 0;

    if (!beehiveCacheInitialized) {
        cachedBeehiveEntity = findBeehive(ctx.world);
        if (cachedBeehiveEntity) |e| {
            if (ctx.world.getGridPosition(e)) |gp| {
                cachedBeehiveGridX = gp.x;
                cachedBeehiveGridY = gp.y;
            }
        }
        beehiveCacheInitialized = true;
    }

    if (currentStaggerGroup == 0) {
        buildAvailableFlowersCache(ctx.world);
    }

    const beehiveWorldPos = getWorldPosFromGrid(cachedBeehiveGridX, cachedBeehiveGridY, ctx.gridOffset, ctx.gridScale);

    var beeIndex: usize = 0;
    var iter = ctx.world.iterateBees();
    while (iter.next()) |entity| {
        const isInStaggerGroup = beeIndex % STAGGER_GROUPS == currentStaggerGroup;
        beeIndex += 1;

        const beeAI = ctx.world.getBeeAI(entity) orelse continue;
        const position = ctx.world.getPosition(entity) orelse continue;

        if (ctx.world.getLifespan(entity)) |lifespan| {
            if (lifespan.isDead()) continue;
        }

        // Off-frame bees: interpolate toward cached target for smooth visuals.
        // Uses cached grid coords → no HashMap lookup per skipped bee.
        if (!isInStaggerGroup) {
            if (beeAI.targetLocked) {
                const targetPos = if (beeAI.carryingPollen)
                    beehiveWorldPos
                else
                    getWorldPosFromGrid(beeAI.targetGridX, beeAI.targetGridY, ctx.gridOffset, ctx.gridScale);
                moveTowards(position, targetPos, ctx.deltaTime);
            } else if (beeAI.scatterTimer > 0) {
                beeAI.scatterTimer -= ctx.deltaTime;
                performRandomWalk(beeAI, position, ctx.deltaTime);
            }
            continue;
        }

        if (beeAI.searchCooldown > 0) beeAI.searchCooldown -= scaledDeltaTime;

        if (beeAI.scatterTimer > 0) {
            beeAI.scatterTimer -= scaledDeltaTime;
            performRandomWalk(beeAI, position, scaledDeltaTime);
            continue;
        }

        if (checkPollination and beeAI.carryingPollen) {
            try handlePollination(ctx.world, beeAI, position, ctx.gridOffset, ctx.gridScale, ctx.gridWidth, ctx.gridHeight, ctx.texturesRef);
        }

        if (beeAI.carryingPollen) {
            if (!beeAI.targetLocked) {
                beeAI.targetEntity = cachedBeehiveEntity;
                if (beeAI.targetEntity != null) {
                    beeAI.targetLocked = true;
                    beeAI.targetGridX = cachedBeehiveGridX;
                    beeAI.targetGridY = cachedBeehiveGridY;
                }
            }

            const distance = rl.math.vector2Distance(position.toVector2(), beehiveWorldPos);
            if (distance < 30.0) {
                if (ctx.world.getPollenCollector(entity)) |collector| {
                    if (collector.pollenCollected > 0) {
                        const newHoney = collector.pollenCollected * ctx.honeyFactor * ctx.labs.honeyMultiplier() * ctx.prestige.globalMul();
                        ctx.resources.addHoney(newHoney);
                        ctx.prestige.trackHoney(newHoney);
                        ctx.frameHoneyGain.* += newHoney;
                        collector.pollenCollected = 0;

                        beeAI.carryingPollen = false;
                        beeAI.targetLocked = false;
                        beeAI.targetEntity = null;
                    }
                }
            } else {
                moveTowardsWithSpeed(position, beehiveWorldPos, scaledDeltaTime, beeAI.beeType.getSpeedMultiplier());
            }
            continue;
        }

        if (!beeAI.targetLocked) {
            if (beeAI.searchCooldown <= 0) {
                const found = findNearestFlowerFromCache(ctx.world, position.toVector2(), ctx.gridOffset, ctx.gridScale);
                if (found) |hit| {
                    beeAI.targetEntity = hit.entity;
                    beeAI.targetGridX = hit.gridX;
                    beeAI.targetGridY = hit.gridY;
                    beeAI.targetLocked = true;
                    ctx.world.incrementFlowerTarget(hit.entity);
                } else {
                    beeAI.searchCooldown = SEARCH_COOLDOWN;
                }
            }

            if (!beeAI.targetLocked) {
                performRandomWalk(beeAI, position, scaledDeltaTime);
            }
            continue;
        }

        const targetEntity = beeAI.targetEntity orelse {
            performRandomWalk(beeAI, position, scaledDeltaTime);
            continue;
        };

        const targetFlower = ctx.world.getFlowerGrowth(targetEntity);
        if (targetFlower == null) {
            ctx.world.decrementFlowerTarget(targetEntity);
            beeAI.targetLocked = false;
            beeAI.targetEntity = null;
            continue;
        }

        const targetPos = getWorldPosFromGrid(beeAI.targetGridX, beeAI.targetGridY, ctx.gridOffset, ctx.gridScale);
        const distance = rl.math.vector2Distance(position.toVector2(), targetPos);

        if (distance < 5.0) {
            if (targetFlower.?.state == 4 and targetFlower.?.hasPollen) {
                targetFlower.?.hasPollen = false;
                beeAI.carryingPollen = true;

                if (ctx.world.getPollenCollector(entity)) |collector| {
                    const collectionMultiplier = beeAI.beeType.getCollectionMultiplier();
                    collector.collect(1.0 * targetFlower.?.pollenMultiplier * collectionMultiplier);
                }

                // Short dawdle after collecting, then head to the hive — long
                // scatter here was the main throttle on honey throughput.
                beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(6, 14))) / 10.0;
            }

            ctx.world.decrementFlowerTarget(targetEntity);
            beeAI.targetLocked = false;
            beeAI.targetEntity = null;
        } else {
            moveTowardsWithSpeed(position, targetPos, scaledDeltaTime, beeAI.beeType.getSpeedMultiplier());
        }
    }

    currentStaggerGroup = (currentStaggerGroup + 1) % STAGGER_GROUPS;
}

fn moveTowards(position: anytype, target: rl.Vector2, deltaTime: f32) void {
    moveTowardsWithSpeed(position, target, deltaTime, 1.0);
}

fn moveTowardsWithSpeed(position: anytype, target: rl.Vector2, deltaTime: f32, speedMultiplier: f32) void {
    const speed = MOVEMENT_LEAP_FACTOR * speedMultiplier;
    position.x += (target.x - position.x) * speed * deltaTime;
    position.y += (target.y - position.y) * speed * deltaTime;
}

fn buildAvailableFlowersCache(world: *World) void {
    availableFlowerCount = 0;

    var iter = world.iterateFlowers();
    while (iter.next()) |entity| {
        if (availableFlowerCount >= MAX_AVAILABLE_FLOWERS) break;

        if (world.getFlowerGrowth(entity)) |growth| {
            if (growth.state != 4 or !growth.hasPollen) continue;

            const beesNearFlower = world.getFlowerTargetCount(entity);
            if (beesNearFlower >= 3) continue;

            if (world.getGridPosition(entity)) |gridPos| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) continue;
                }

                availableFlowers[availableFlowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x,
                    .gridY = gridPos.y,
                };
                availableFlowerCount += 1;
            }
        }
    }
}

const FlowerHit = struct {
    entity: Entity,
    gridX: f32,
    gridY: f32,
};

fn findNearestFlowerFromCache(world: *World, beePosition: rl.Vector2, gridOffset: rl.Vector2, gridScale: f32) ?FlowerHit {
    var best: f32 = std.math.floatMax(f32);
    var hit: ?FlowerHit = null;

    for (0..availableFlowerCount) |i| {
        const flower = availableFlowers[i];
        if (world.getFlowerTargetCount(flower.entity) >= 3) continue;

        const worldPos = getWorldPosFromGrid(flower.gridX, flower.gridY, gridOffset, gridScale);
        const d = rl.math.vector2DistanceSqr(worldPos, beePosition);
        if (d < best) {
            best = d;
            hit = .{ .entity = flower.entity, .gridX = flower.gridX, .gridY = flower.gridY };
        }
    }

    return hit;
}

fn findBeehive(world: *World) ?Entity {
    var iter = world.entityToBeehive.keyIterator();
    if (iter.next()) |entity| return entity.*;
    return null;
}

fn getWorldPosFromGrid(gridX: f32, gridY: f32, offset: rl.Vector2, gridScale: f32) rl.Vector2 {
    const tileWidth: f32 = 32;
    const tileHeight: f32 = 32;
    const flowerWidth: f32 = 32;
    const flowerHeight: f32 = 32;
    const flowerScale: f32 = 2;

    const tilePosition = utils.isoToXY(gridX, gridY, tileWidth, tileHeight, offset.x, offset.y, gridScale);
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
    if (!beeAI.beeType.canSpawnFlowers()) return;

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
        if (rl.getRandomValue(1, 100) <= 20) {
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
