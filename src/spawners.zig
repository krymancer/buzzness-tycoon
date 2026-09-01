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

/// Flower costs for planting (see components.FlowerType.stats).
pub const FLOWER_COSTS = struct {
    pub const rose: f32 = components.FlowerType.rose.stats().plantCost;
    pub const tulip: f32 = components.FlowerType.tulip.stats().plantCost;
    pub const dandelion: f32 = components.FlowerType.dandelion.stats().plantCost;
};

/// Fresh flower lifespan in seconds: 60-120 base, scaled per type (#71).
pub fn newFlowerLifespan(flowerType: components.FlowerType) f32 {
    return @as(f32, @floatFromInt(rl.getRandomValue(60, 120))) * flowerType.stats().lifespanMul;
}

/// Bee cost for purchasing (per type)
pub const BEE_COST: f32 = 10.0;

/// Prestige price multiplier applied to bee purchases (PrestigeState.costMul).
/// game.zig refreshes it on run reset and on save load.
pub var beeCostMul: f32 = 1.0;

pub const BEE_TYPE_COSTS = struct {
    pub const worker: f32 = 10.0;
    pub const swift: f32 = 100.0;
    pub const efficient: f32 = 500.0;
    pub const gardener: f32 = 2000.0;

    pub fn get(beeType: components.BeeType) f32 {
        const base: f32 = switch (beeType) {
            .worker => worker,
            .swift => swift,
            .efficient => efficient,
            .gardener => gardener,
        };
        return base * beeCostMul;
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

/// Bee Vitality node: multiplies the lifespan of newly spawned bees.
/// (game.zig also extends already-living bees when the node is bought.)
pub var beeLifespanMul: f32 = 1.0;
pub const BEE_LIFESPAN_PER_LEVEL: f32 = 1.2;

pub fn beeLifespanMulForLevel(level: u16) f32 {
    return std.math.pow(f32, BEE_LIFESPAN_PER_LEVEL, @floatFromInt(level));
}

/// Fresh bee lifespan range in seconds. Bees are mortal (#69): the base is
/// long enough that a colony is not a re-buy treadmill (a 10-honey worker
/// outlives the seconds it takes to afford another by two orders of
/// magnitude), and a bee that dies carrying pollen spends it on +50% more
/// life instead (bees.Store.age), so busy bees last well past this.
pub const BEE_LIFESPAN_MIN_S: i32 = 480;
pub const BEE_LIFESPAN_MAX_S: i32 = 960;

/// Fresh bee lifespan in seconds, stretched by Bee Vitality.
pub fn newBeeLifespan() f32 {
    return @as(f32, @floatFromInt(rl.getRandomValue(BEE_LIFESPAN_MIN_S, BEE_LIFESPAN_MAX_S))) * beeLifespanMul;
}

/// Add a worker to the colony (see spawnBeeWithType).
pub fn spawnBee(world: *World, grid: *const Grid) !bool {
    return spawnBeeWithType(world, grid, .worker);
}

/// Add a bee of `beeType` to the colony. While the simulation cap has room
/// it appears at a random spot on the meadow; past it the bee is counted
/// and the simulated mix re-proportions next frame (bees.zig). Returns
/// false when the type is at its ceiling.
pub fn spawnBeeWithType(world: *World, grid: *const Grid, beeType: components.BeeType) !bool {
    syncMeadow(world, grid);
    return world.bees.add(beeType);
}

/// Keep the bee store's idea of the meadow in step with the camera so
/// spawns land on the field.
pub fn syncMeadow(world: *World, grid: *const Grid) void {
    world.bees.meadow = .{
        .offset = grid.offset,
        .scale = grid.scale,
        .width = grid.width,
        .height = grid.height,
    };
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
    try world.addLifespan(flowerEntity, components.Lifespan.init(newFlowerLifespan(flowersToFlowerType(flowerType))));

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

/// Merges since the game last drained it (achievements / lifetime stats).
/// Merges come from several systems, so they are counted at the source.
pub var superMergesPending: u32 = 0;

pub fn takeSuperMerges() u32 {
    const n = superMergesPending;
    superMergesPending = 0;
    return n;
}

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
        superMergesPending += 1;
        return true;
    }
    return false;
}

test "flower types differ: cheap-quick-brief dandelion, rich-slow-lasting tulip (#71)" {
    const d = components.FlowerType.dandelion.stats();
    const r = components.FlowerType.rose.stats();
    const t = components.FlowerType.tulip.stats();
    try std.testing.expect(d.plantCost < r.plantCost and r.plantCost < t.plantCost);
    try std.testing.expect(d.pollenMul < r.pollenMul and r.pollenMul < t.pollenMul);
    try std.testing.expect(d.growthMul > r.growthMul and r.growthMul > t.growthMul);
    try std.testing.expect(d.lifespanMul < r.lifespanMul and r.lifespanMul < t.lifespanMul);
    // The stats actually reach the flower and the plant menu.
    try std.testing.expectEqual(t.pollenMul, components.FlowerGrowth.init(.tulip).pollenMultiplier);
    try std.testing.expectEqual(t.plantCost, FLOWER_COSTS.tulip);
    try std.testing.expectEqual(r.pollenMul, components.FlowerGrowth.init(.rose).pollenMultiplier);
}
