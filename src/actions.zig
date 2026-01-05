const std = @import("std");
const World = @import("ecs/world.zig").World;
const Resources = @import("resources.zig").Resources;
const Grid = @import("grid.zig").Grid;
const Textures = @import("textures.zig").Textures;
const spawners = @import("spawners.zig");
const components = @import("ecs/components.zig");
const ui = @import("ui.zig");

/// Result of handling a popup action
pub const ActionResult = struct {
    closePopup: bool = false,
    beeCountDelta: i32 = 0,
    flowerCountDelta: i32 = 0,
};

/// Handles all game actions triggered from popups
pub const ActionHandler = struct {
    world: *World,
    resources: *Resources,
    grid: *const Grid,
    textures: *const Textures,
    beehiveUpgradeCost: *f32,

    pub fn handlePopupAction(
        self: *@This(),
        action: ui.TilePopupAction,
        selectedTileX: i32,
        selectedTileY: i32,
    ) !ActionResult {
        var result = ActionResult{};

        switch (action) {
            .close => {
                result.closePopup = true;
            },
            .buy_worker_bee => {
                if (self.resources.spendHoney(spawners.BEE_TYPE_COSTS.worker)) {
                    _ = try spawners.spawnBeeWithType(self.world, self.grid, self.textures, .worker);
                    result.beeCountDelta = 1;
                }
            },
            .buy_swift_bee => {
                if (self.resources.spendHoney(spawners.BEE_TYPE_COSTS.swift)) {
                    _ = try spawners.spawnBeeWithType(self.world, self.grid, self.textures, .swift);
                    result.beeCountDelta = 1;
                }
            },
            .buy_efficient_bee => {
                if (self.resources.spendHoney(spawners.BEE_TYPE_COSTS.efficient)) {
                    _ = try spawners.spawnBeeWithType(self.world, self.grid, self.textures, .efficient);
                    result.beeCountDelta = 1;
                }
            },
            .buy_gardener_bee => {
                if (self.resources.spendHoney(spawners.BEE_TYPE_COSTS.gardener)) {
                    _ = try spawners.spawnBeeWithType(self.world, self.grid, self.textures, .gardener);
                    result.beeCountDelta = 1;
                }
            },
            .upgrade_beehive => {
                if (self.resources.spendHoney(self.beehiveUpgradeCost.*)) {
                    var beehiveIter = self.world.entityToBeehive.keyIterator();
                    if (beehiveIter.next()) |beehiveEntity| {
                        if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                            beehive.honeyConversionFactor *= 2.0;
                            self.beehiveUpgradeCost.* *= 2.0;
                        }
                    }
                }
            },
            .upgrade_storage => {
                _ = self.resources.upgradeStorage();
            },
            .upgrade_growth_boost => {
                _ = self.resources.upgradeGrowthBoost();
            },
            .upgrade_flower => {
                if (self.world.getFlowerAtGrid(selectedTileX, selectedTileY)) |flowerEntity| {
                    if (self.world.getFlowerGrowth(flowerEntity)) |growth| {
                        const upgradeCost = 20.0 * growth.pollenMultiplier;
                        if (self.resources.spendHoney(upgradeCost)) {
                            growth.pollenMultiplier += 0.5;
                        }
                    }
                }
            },
            .plant_rose => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.rose)) {
                    _ = try spawners.spawnFlower(self.world, self.textures, .rose, selectedTileX, selectedTileY);
                    result.flowerCountDelta = 1;
                    result.closePopup = true;
                }
            },
            .plant_tulip => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.tulip)) {
                    _ = try spawners.spawnFlower(self.world, self.textures, .tulip, selectedTileX, selectedTileY);
                    result.flowerCountDelta = 1;
                    result.closePopup = true;
                }
            },
            .plant_dandelion => {
                if (self.resources.spendHoney(spawners.FLOWER_COSTS.dandelion)) {
                    _ = try spawners.spawnFlower(self.world, self.textures, .dandelion, selectedTileX, selectedTileY);
                    result.flowerCountDelta = 1;
                    result.closePopup = true;
                }
            },
            .none => {},
        }

        return result;
    }

    /// Rebirth a dying flower - reset lifespan and give bonuses
    pub fn rebirthFlower(self: *@This(), entity: u32) void {
        if (self.world.getLifespan(entity)) |lifespan| {
            const baseLifespan = lifespan.timeSpan;
            lifespan.timeAlive = 0;
            lifespan.totalTimeAlive = 0;
            lifespan.timeSpan = baseLifespan * 1.2; // 20% longer life on rebirth
        }

        if (self.world.getFlowerGrowth(entity)) |growth| {
            growth.pollenMultiplier += 0.25; // +0.25 bonus on rebirth
            growth.hasPollen = true; // Restore pollen
        }
    }

    /// Boost a flower's growth by one stage
    pub fn boostFlowerGrowth(self: *@This(), entity: u32) void {
        if (self.resources.useGrowthBoost()) {
            if (self.world.getFlowerGrowth(entity)) |growth| {
                if (growth.state < 4) {
                    growth.state += 1;
                }
                if (growth.state >= 4) {
                    growth.hasPollen = true;
                }
            }
        }
    }

    /// Get the current beehive honey conversion factor
    pub fn getBeehiveHoneyFactor(self: *@This()) f32 {
        var beehiveIter = self.world.entityToBeehive.keyIterator();
        if (beehiveIter.next()) |beehiveEntity| {
            if (self.world.getBeehive(beehiveEntity.*)) |beehive| {
                return beehive.honeyConversionFactor;
            }
        }
        return 1.0;
    }
};
