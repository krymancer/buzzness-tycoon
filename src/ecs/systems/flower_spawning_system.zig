const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const components = @import("../components.zig");
const utils = @import("../../utils.zig");
const textures = @import("../../textures.zig");
const Flowers = textures.Flowers;
const spawners = @import("../../spawners.zig");
const meadow_plan = @import("../../meadow_plan.zig");

var emptyCellTimer: f32 = 0;
// The meadow re-seeds itself fairly briskly so bees rarely run out of targets —
// idle progression is bottlenecked by ripe pollen, so keeping flowers plentiful
// is what makes buying more bees actually pay off.
const EMPTY_CELL_CHECK_INTERVAL: f32 = 2.0;
// Spawn rolls per check scale with the meadow so Grid Rings actually raise
// flower supply (a flat rate capped the field at ~25 flowers, whatever the
// size). 17x17 = 289 cells -> 2 rolls; 37x37 (10 rings) -> 9.
const SPAWN_ROLLS_PER_CELL: f32 = 0.0065;

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
        const cells: f32 = @floatFromInt(gridWidth * gridHeight);
        const rolls: usize = @intFromFloat(@max(1.0, @ceil(cells * SPAWN_ROLLS_PER_CELL)));
        for (0..rolls) |_| {
            try trySpawnFlowerInEmptyCell(world, gridWidth, gridHeight, texturesRef);
        }
        // One extra roll aimed at the plan: nature fills the blueprint too,
        // just slower than gardeners.
        if (meadow_plan.count() > 0) try trySpawnOnPlannedGap(world, gridWidth, gridHeight, texturesRef);
    }
}

fn spawnAt(world: *World, gridI: usize, gridJ: usize, flowerType: Flowers, texturesRef: anytype) !void {
    const flowerTexture = texturesRef.getFlowerTexture(flowerType);
    const flowerEntity = try world.createEntity();
    try world.addGridPosition(flowerEntity, components.GridPosition.init(@floatFromInt(gridI), @floatFromInt(gridJ)));
    try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(textures.flowersToFlowerType(flowerType)));
    try world.addLifespan(flowerEntity, components.Lifespan.init(spawners.newFlowerLifespan(textures.flowersToFlowerType(flowerType))));
    world.registerFlowerAtGrid(@intCast(gridI), @intCast(gridJ), flowerEntity);
    _ = try spawners.tryMergeSuperFlower(world, @intCast(gridI), @intCast(gridJ));
}

/// Pick a random planned, empty cell and sprout its planned type there.
fn trySpawnOnPlannedGap(world: *World, gridWidth: usize, gridHeight: usize, texturesRef: anytype) !void {
    var gaps: [meadow_plan.CELLS]u32 = undefined;
    var n: usize = 0;
    for (0..@min(gridHeight, meadow_plan.MAX)) |j| {
        for (0..@min(gridWidth, meadow_plan.MAX)) |i| {
            if (meadow_plan.get(@intCast(i), @intCast(j)) == null) continue;
            if (world.hasFlowerAtGrid(@intCast(i), @intCast(j))) continue;
            gaps[n] = @intCast(j * meadow_plan.MAX + i);
            n += 1;
        }
    }
    if (n == 0) return;
    const pick = gaps[@intCast(rl.getRandomValue(0, @intCast(n - 1)))];
    const i: usize = pick % meadow_plan.MAX;
    const j: usize = pick / meadow_plan.MAX;
    const planned = meadow_plan.get(@intCast(i), @intCast(j)) orelse return;
    try spawnAt(world, i, j, spawners.flowerTypeToFlowers(planned), texturesRef);
}

fn getRandomFlowerType() Flowers {
    return @enumFromInt(rl.getRandomValue(0, Flowers.count - 1));
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
                // A planned cell sprouts what the plan says.
                const flowerType: Flowers = if (meadow_plan.get(@intCast(gridI), @intCast(gridJ))) |planned|
                    spawners.flowerTypeToFlowers(planned)
                else
                    getRandomFlowerType();
                try spawnAt(world, gridI, gridJ, flowerType, texturesRef);
                return;
            }
        }
    }
}
