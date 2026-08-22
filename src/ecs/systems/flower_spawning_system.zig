const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const components = @import("../components.zig");
const utils = @import("../../utils.zig");
const textures = @import("../../textures.zig");
const Flowers = textures.Flowers;
const spawners = @import("../../spawners.zig");

var emptyCellTimer: f32 = 0;
// The meadow re-seeds itself fairly briskly so bees rarely run out of targets —
// idle progression is bottlenecked by ripe pollen, so keeping flowers plentiful
// is what makes buying more bees actually pay off.
const EMPTY_CELL_CHECK_INTERVAL: f32 = 2.0;

pub fn update(
    world: *World,
    deltaTime: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    gridWidth: usize,
    gridHeight: usize,
    texturesRef: anytype,
) !void {
    _ = gridOffset;
    _ = gridScale;

    emptyCellTimer += deltaTime;
    if (emptyCellTimer >= EMPTY_CELL_CHECK_INTERVAL) {
        emptyCellTimer = 0;
        try trySpawnFlowerInEmptyCell(world, gridWidth, gridHeight, texturesRef);
    }
}

fn getRandomFlowerType() Flowers {
    return switch (rl.getRandomValue(1, 3)) {
        1 => .rose,
        2 => .dandelion,
        3 => .tulip,
        else => .rose,
    };
}

fn trySpawnFlowerInEmptyCell(world: *World, gridWidth: usize, gridHeight: usize, texturesRef: anytype) !void {
    const centerX: usize = (gridWidth - 1) / 2;
    const centerY: usize = (gridHeight - 1) / 2;

    var attempts: usize = 0;
    while (attempts < 5) : (attempts += 1) {
        const gridI: usize = @intCast(rl.getRandomValue(0, @intCast(gridWidth - 1)));
        const gridJ: usize = @intCast(rl.getRandomValue(0, @intCast(gridHeight - 1)));

        if (gridI == centerX and gridJ == centerY) continue;

        if (!world.hasFlowerAtGrid(@intCast(gridI), @intCast(gridJ))) {
            if (rl.getRandomValue(1, 100) <= 55) {
                const flowerType = getRandomFlowerType();
                const flowerTexture = texturesRef.getFlowerTexture(flowerType);

                const flowerEntity = try world.createEntity();
                try world.addGridPosition(flowerEntity, components.GridPosition.init(@floatFromInt(gridI), @floatFromInt(gridJ)));
                try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
                try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(textures.flowersToFlowerType(flowerType)));
                try world.addLifespan(flowerEntity, components.Lifespan.init(@floatFromInt(rl.getRandomValue(60, 120))));
                world.registerFlowerAtGrid(@intCast(gridI), @intCast(gridJ), flowerEntity);
                _ = try spawners.tryMergeSuperFlower(world, @intCast(gridI), @intCast(gridJ));
                return;
            }
        }
    }
}
