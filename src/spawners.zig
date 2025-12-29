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

/// Bee cost for purchasing
pub const BEE_COST: f32 = 10.0;

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
    const randomPos = grid.getRandomPositionInBounds();

    const beeEntity = try world.createEntity();
    try world.addPosition(beeEntity, components.Position.init(randomPos.x, randomPos.y));
    try world.addSprite(beeEntity, components.Sprite.init(textures.bee, 32, 32, 1));
    try world.addBeeAI(beeEntity, components.BeeAI.init());
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

    return spawnFlower(world, textures, flowerType, gridX, gridY);
}
