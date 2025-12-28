const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const components = @import("../components.zig");
const utils = @import("../../utils.zig");
const Flowers = @import("../../textures.zig").Flowers;

var emptyCellTimer: f32 = 0;
const EMPTY_CELL_CHECK_INTERVAL: f32 = 5.0; // Check every 5 seconds

// Helper to convert texture Flowers enum to component FlowerType
fn flowersToFlowerType(flower: Flowers) components.FlowerType {
    return switch (flower) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

pub fn update(
    world: *World,
    deltaTime: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    gridWidth: usize,
    gridHeight: usize,
    textures: anytype,
) !void {
    _ = gridOffset;
    _ = gridScale;

    // Periodically spawn flowers in empty cells
    emptyCellTimer += deltaTime;
    if (emptyCellTimer >= EMPTY_CELL_CHECK_INTERVAL) {
        emptyCellTimer = 0;
        try trySpawnFlowerInEmptyCell(world, gridWidth, gridHeight, textures);
    }
}

fn trySpawnFlower(
    world: *World,
    beePosition: rl.Vector2,
    gridOffset: rl.Vector2,
    gridScale: f32,
    gridWidth: usize,
    gridHeight: usize,
    textures: anytype,
) !bool {
    const gridPos = utils.worldToGrid(beePosition, gridOffset, gridScale);
    const gridI = @as(usize, @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(gridWidth - 1)), gridPos.x))));
    const gridJ = @as(usize, @intFromFloat(@max(0, @min(@as(f32, @floatFromInt(gridHeight - 1)), gridPos.y))));

    var iter = try world.queryEntitiesWithFlowerGrowth();
    defer iter.deinit();

    while (iter.next()) |entity| {
        if (world.getGridPosition(entity)) |existingGridPos| {
            if (world.getLifespan(entity)) |lifespan| {
                if (!lifespan.isDead() and
                    @as(usize, @intFromFloat(existingGridPos.x)) == gridI and
                    @as(usize, @intFromFloat(existingGridPos.y)) == gridJ)
                {
                    return false;
                }
            }
        }
    }

    var iter2 = try world.queryEntitiesWithFlowerGrowth();
    defer iter2.deinit();

    while (iter2.next()) |entity| {
        if (world.getGridPosition(entity)) |existingGridPos| {
            if (world.getFlowerGrowth(entity)) |growth| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead() and
                        @as(usize, @intFromFloat(existingGridPos.x)) == gridI and
                        @as(usize, @intFromFloat(existingGridPos.y)) == gridJ)
                    {
                        const flowerType = getRandomFlowerType();
                        const flowerTexture = textures.getFlowerTexture(flowerType);

                        if (world.getSprite(entity)) |sprite| {
                            sprite.texture = flowerTexture;
                        }

                        growth.* = components.FlowerGrowth.init(flowersToFlowerType(flowerType));
                        lifespan.timeAlive = 0;
                        lifespan.totalTimeAlive = 0;

                        return true;
                    }
                }
            }
        }
    }

    const flowerType = getRandomFlowerType();
    const flowerTexture = textures.getFlowerTexture(flowerType);

    const flowerEntity = try world.createEntity();
    try world.addGridPosition(flowerEntity, components.GridPosition.init(@as(f32, @floatFromInt(gridI)), @as(f32, @floatFromInt(gridJ))));
    try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(flowersToFlowerType(flowerType)));
    try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));

    // Register flower in spatial lookup
    world.registerFlowerAtGrid(@intCast(gridI), @intCast(gridJ), flowerEntity);

    return true;
}

fn getRandomFlowerType() Flowers {
    const rl_module = @import("raylib");
    const x = rl_module.getRandomValue(1, 3);
    return switch (x) {
        1 => Flowers.rose,
        2 => Flowers.dandelion,
        3 => Flowers.tulip,
        else => Flowers.rose,
    };
}

fn trySpawnFlowerInEmptyCell(world: *World, gridWidth: usize, gridHeight: usize, textures: anytype) !void {
    const centerX: usize = (gridWidth - 1) / 2;
    const centerY: usize = (gridHeight - 1) / 2;

    // Try a few random cells to find an empty one
    var attempts: usize = 0;
    while (attempts < 5) : (attempts += 1) {
        const gridI: usize = @intCast(rl.getRandomValue(0, @intCast(gridWidth - 1)));
        const gridJ: usize = @intCast(rl.getRandomValue(0, @intCast(gridHeight - 1)));

        // Skip beehive tile
        if (gridI == centerX and gridJ == centerY) {
            continue;
        }

        // Check if this cell already has a flower - O(1) lookup
        const hasFlower = world.hasFlowerAtGrid(@intCast(gridI), @intCast(gridJ));

        // If empty, 30% chance to spawn a flower
        if (!hasFlower) {
            if (rl.getRandomValue(1, 100) <= 30) {
                const flowerType = getRandomFlowerType();
                const flowerTexture = textures.getFlowerTexture(flowerType);

                const flowerEntity = try world.createEntity();
                try world.addGridPosition(flowerEntity, components.GridPosition.init(@as(f32, @floatFromInt(gridI)), @as(f32, @floatFromInt(gridJ))));
                try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
                try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(flowersToFlowerType(flowerType)));
                try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));

                // Register flower in spatial lookup
                world.registerFlowerAtGrid(@intCast(gridI), @intCast(gridJ), flowerEntity);
                return; // Successfully spawned
            }
        }
    }
}
