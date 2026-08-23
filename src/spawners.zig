//! Entity spawning helpers
//!
//! Provides functions to create game entities (bees, flowers) with all required components.
//! This centralizes entity creation logic that was previously scattered across game.zig.

const rl = @import("raylib");
const std = @import("std");

const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");
const Textures = @import("textures.zig").Textures;
const Flowers = @import("textures.zig").Flowers;
const Grid = @import("grid.zig").Grid;
const scale_sync_system = @import("ecs/systems/scale_sync_system.zig");

/// Flower costs for planting
pub const FLOWER_COSTS = struct {
    pub const rose: f32 = 10.0;
    pub const tulip: f32 = 15.0;
    pub const dandelion: f32 = 5.0;
};

/// Bee cost for purchasing (per type)
pub const BEE_COST: f32 = 10.0;

pub const BEE_TYPE_COSTS = struct {
    pub const worker: f32 = 10.0;
    pub const swift: f32 = 100.0;
    pub const efficient: f32 = 500.0;
    pub const gardener: f32 = 2000.0;

    pub fn get(beeType: components.BeeType) f32 {
        return switch (beeType) {
            .worker => worker,
            .swift => swift,
            .efficient => efficient,
            .gardener => gardener,
        };
    }
};

/// Convert texture Flowers enum to component FlowerType
pub fn flowersToFlowerType(flower: Flowers) components.FlowerType {
    return switch (flower) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

/// Convert component FlowerType to texture Flowers enum
pub fn flowerTypeToFlowers(flowerType: components.FlowerType) Flowers {
    return switch (flowerType) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

/// Spawn a new bee at a random position within the grid bounds
pub fn spawnBee(world: *World, grid: *const Grid, textures: *const Textures) !u32 {
    return spawnBeeWithType(world, grid, textures, .worker);
}

/// Spawn a new bee of a specific type at a random position within the grid bounds
pub fn spawnBeeWithType(world: *World, grid: *const Grid, textures: *const Textures, beeType: components.BeeType) !u32 {
    const randomPos = grid.getRandomPositionInBounds();

    const beeEntity = try world.createEntity();
    try world.addPosition(beeEntity, components.Position.init(randomPos.x, randomPos.y));
    try world.addSprite(beeEntity, components.Sprite.init(textures.bee, 32, 32, 1));
    try world.addBeeAI(beeEntity, components.BeeAI.initWithType(beeType));
    try world.addLifespan(beeEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 140))));
    try world.addPollenCollector(beeEntity, components.PollenCollector.init());
    try world.addScaleSync(beeEntity, components.ScaleSync.init(1));

    if (world.getScaleSync(beeEntity)) |scaleSync| {
        scaleSync.updateFromGrid(1, grid.scale);
    }

    // Mark scale sync system dirty to ensure new entity gets updated
    scale_sync_system.markDirty();

    return beeEntity;
}

/// Spawn a new flower at the specified grid position
pub fn spawnFlower(
    world: *World,
    textures: *const Textures,
    flowerType: Flowers,
    gridX: i32,
    gridY: i32,
) !u32 {
    const flowerTexture = textures.getFlowerTexture(flowerType);
    const gridXf: f32 = @floatFromInt(gridX);
    const gridYf: f32 = @floatFromInt(gridY);

    const flowerEntity = try world.createEntity();
    try world.addGridPosition(flowerEntity, components.GridPosition.init(gridXf, gridYf));
    try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(flowersToFlowerType(flowerType)));
    try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));

    // Register flower in spatial lookup
    world.registerFlowerAtGrid(gridX, gridY, flowerEntity);

    return flowerEntity;
}

// Test helper: fabricate a flower without loading textures (no GL needed).
fn spawnTestFlower(world: *World, flowerType: components.FlowerType, gridX: i32, gridY: i32) !u32 {
    const dummyTexture = rl.Texture{ .id = 0, .width = 32, .height = 32, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    const entity = try world.createEntity();
    try world.addGridPosition(entity, components.GridPosition.init(@floatFromInt(gridX), @floatFromInt(gridY)));
    try world.addSprite(entity, components.Sprite.init(dummyTexture, 32, 32, 2));
    try world.addFlowerGrowth(entity, components.FlowerGrowth.init(flowerType));
    try world.addLifespan(entity, components.Lifespan.init(100));
    world.registerFlowerAtGrid(gridX, gridY, entity);
    return entity;
}

test "merging is inert until the Super Flowers node is unlocked" {
    superFlowersUnlocked = false;
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try spawnTestFlower(&world, .rose, 2, 2);
    _ = try spawnTestFlower(&world, .rose, 3, 2);
    _ = try spawnTestFlower(&world, .rose, 2, 3);
    _ = try spawnTestFlower(&world, .rose, 3, 3);
    try std.testing.expect(!(try tryMergeSuperFlower(&world, 3, 3)));
}

test "2x2 same-type block merges into a super flower with 8x yield" {
    superFlowersUnlocked = true;
    defer superFlowersUnlocked = false;
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try spawnTestFlower(&world, .rose, 2, 2);
    _ = try spawnTestFlower(&world, .rose, 3, 2);
    _ = try spawnTestFlower(&world, .rose, 2, 3);
    const last = try spawnTestFlower(&world, .rose, 3, 3);
    _ = last;

    try std.testing.expect(try tryMergeSuperFlower(&world, 3, 3));

    const keeper = world.getFlowerAtGrid(2, 2).?;
    // All four cells resolve to the same merged entity.
    try std.testing.expectEqual(keeper, world.getFlowerAtGrid(3, 2).?);
    try std.testing.expectEqual(keeper, world.getFlowerAtGrid(2, 3).?);
    try std.testing.expectEqual(keeper, world.getFlowerAtGrid(3, 3).?);

    const growth = world.getFlowerGrowth(keeper).?;
    try std.testing.expect(growth.isSuper);
    // 4 flowers at x1 each, doubled: 8x a lone flower.
    try std.testing.expectEqual(@as(f32, 8.0), growth.pollenMultiplier);
    const sprite = world.getSprite(keeper).?;
    try std.testing.expectEqual(SUPER_SPRITE_SCALE, sprite.scale);

    // The three absorbed entities are queued for destruction.
    try std.testing.expectEqual(@as(usize, 3), world.entitiesToDestroy.items.len);
}

test "mixed-type or incomplete blocks do not merge" {
    superFlowersUnlocked = true;
    defer superFlowersUnlocked = false;
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try spawnTestFlower(&world, .rose, 2, 2);
    _ = try spawnTestFlower(&world, .rose, 3, 2);
    _ = try spawnTestFlower(&world, .rose, 2, 3);
    _ = try spawnTestFlower(&world, .tulip, 3, 3);
    try std.testing.expect(!(try tryMergeSuperFlower(&world, 3, 3)));

    // Three same-type flowers + one empty cell: still no merge.
    var world2 = World.init(std.testing.allocator);
    defer world2.deinit();
    _ = try spawnTestFlower(&world2, .rose, 2, 2);
    _ = try spawnTestFlower(&world2, .rose, 3, 2);
    _ = try spawnTestFlower(&world2, .rose, 2, 3);
    try std.testing.expect(!(try tryMergeSuperFlower(&world2, 2, 3)));
}

test "a super flower does not chain-merge into a neighbouring block" {
    superFlowersUnlocked = true;
    defer superFlowersUnlocked = false;
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try spawnTestFlower(&world, .rose, 2, 2);
    _ = try spawnTestFlower(&world, .rose, 3, 2);
    _ = try spawnTestFlower(&world, .rose, 2, 3);
    _ = try spawnTestFlower(&world, .rose, 3, 3);
    try std.testing.expect(try tryMergeSuperFlower(&world, 3, 3));

    // New same-type flowers next to the super's cells must not re-merge with it.
    _ = try spawnTestFlower(&world, .rose, 4, 2);
    _ = try spawnTestFlower(&world, .rose, 4, 3);
    try std.testing.expect(!(try tryMergeSuperFlower(&world, 4, 3)));
}

/// Spawn the beehive at the center of the grid
pub fn spawnBeehive(world: *World, textures: *const Textures, gridWidth: usize, gridHeight: usize) !u32 {
    const centerX: f32 = @floatFromInt((gridWidth - 1) / 2);
    const centerY: f32 = @floatFromInt((gridHeight - 1) / 2);

    const beehiveEntity = try world.createEntity();
    try world.addGridPosition(beehiveEntity, components.GridPosition.init(centerX, centerY));
    try world.addSprite(beehiveEntity, components.Sprite.init(textures.beehive, 32, 32, 2));
    try world.addBeehive(beehiveEntity, components.Beehive.init());

    return beehiveEntity;
}

/// Spawn a random flower type at the specified grid position
pub fn spawnRandomFlower(
    world: *World,
    textures: *const Textures,
    gridX: i32,
    gridY: i32,
) !u32 {
    const x = rl.getRandomValue(1, 3);
    const flowerType: Flowers = switch (x) {
        1 => .rose,
        2 => .dandelion,
        3 => .tulip,
        else => .rose,
    };

    const entity = try spawnFlower(world, textures, flowerType, gridX, gridY);
    _ = try tryMergeSuperFlower(world, gridX, gridY);
    return entity;
}

/// SUPER flower tuning: a merged flower yields double what its four parts
/// would have (pollenMultiplier sum x2 => 8x a lone base flower), and the
/// sprite doubles from the normal flower scale of 2 to cover the 2x2 block.
pub const SUPER_YIELD_FACTOR: f32 = 2.0;
pub const SUPER_SPRITE_SCALE: f32 = 4.0;

/// Gate: merging only happens once the "Super Flowers" tree node is owned.
/// game.zig keeps this in sync with the upgrade tree (purchase/load/prestige).
pub var superFlowersUnlocked: bool = false;

/// Mark an existing flower entity as SUPER: double-size sprite and ownership
/// of all four cells of the 2x2 block anchored at its grid position.
pub fn applySuperForm(world: *World, entity: u32, anchorX: i32, anchorY: i32) void {
    if (world.getFlowerGrowth(entity)) |growth| growth.isSuper = true;
    if (world.getSprite(entity)) |sprite| sprite.scale = SUPER_SPRITE_SCALE;
    world.registerFlowerAtGrid(anchorX, anchorY, entity);
    world.registerFlowerAtGrid(anchorX + 1, anchorY, entity);
    world.registerFlowerAtGrid(anchorX, anchorY + 1, entity);
    world.registerFlowerAtGrid(anchorX + 1, anchorY + 1, entity);
}

/// If the flower at (gridX, gridY) completes a 2x2 block of same-type normal
/// flowers, merge the block into one SUPER flower. Returns true if a merge
/// happened. Call after any spawn/plant; the four candidate blocks containing
/// the new cell are checked.
pub fn tryMergeSuperFlower(world: *World, gridX: i32, gridY: i32) !bool {
    if (!superFlowersUnlocked) return false;
    const anchors = [_][2]i32{
        .{ gridX - 1, gridY - 1 },
        .{ gridX, gridY - 1 },
        .{ gridX - 1, gridY },
        .{ gridX, gridY },
    };

    for (anchors) |anchor| {
        const ax = anchor[0];
        const ay = anchor[1];
        const cells = [_][2]i32{
            .{ ax, ay },
            .{ ax + 1, ay },
            .{ ax, ay + 1 },
            .{ ax + 1, ay + 1 },
        };

        var entities: [4]u32 = undefined;
        var blockType: ?components.FlowerType = null;
        var valid = true;
        for (cells, 0..) |cell, i| {
            const entity = world.getFlowerAtGrid(cell[0], cell[1]) orelse {
                valid = false;
                break;
            };
            const growth = world.getFlowerGrowth(entity) orelse {
                valid = false;
                break;
            };
            if (growth.isSuper or growth.isRotten) {
                valid = false;
                break;
            }
            if (world.getLifespan(entity)) |lifespan| {
                if (lifespan.isDead()) {
                    valid = false;
                    break;
                }
            }
            if (blockType) |t| {
                if (growth.flowerType != t) {
                    valid = false;
                    break;
                }
            } else {
                blockType = growth.flowerType;
            }
            entities[i] = entity;
        }
        if (!valid) continue;

        // Merge into the anchor entity; absorb the other three.
        const keeper = entities[0];
        var stateMax: f32 = 0;
        var multiplierSum: f32 = 0;
        var timeSpanMax: f32 = 0;
        var anyPollen = false;
        for (entities) |entity| {
            if (world.getFlowerGrowth(entity)) |growth| {
                stateMax = @max(stateMax, growth.state);
                multiplierSum += growth.pollenMultiplier;
                anyPollen = anyPollen or growth.hasPollen;
            }
            if (world.getLifespan(entity)) |lifespan| {
                timeSpanMax = @max(timeSpanMax, lifespan.timeSpan);
            }
        }

        if (world.getFlowerGrowth(keeper)) |growth| {
            growth.state = stateMax;
            growth.hasPollen = anyPollen and stateMax >= 4;
            growth.pollenMultiplier = multiplierSum * SUPER_YIELD_FACTOR;
        }
        if (world.getLifespan(keeper)) |lifespan| {
            // Merging is a fresh start: full lifespan, best genes of the block.
            lifespan.timeAlive = 0;
            lifespan.totalTimeAlive = 0;
            lifespan.timeSpan = timeSpanMax;
        }

        for (entities[1..]) |entity| {
            world.clearFlowerTargetCount(entity);
            try world.destroyEntity(entity);
        }
        applySuperForm(world, keeper, ax, ay);
        return true;
    }
    return false;
}
