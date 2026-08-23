const std = @import("std");
const World = @import("ecs/world.zig").World;
const Resources = @import("resources.zig").Resources;
const Grid = @import("grid.zig").Grid;
const Textures = @import("textures.zig").Textures;
const spawners = @import("spawners.zig");
const components = @import("ecs/components.zig");

/// Result of a shop purchase.
pub const ActionResult = struct {
    beeCountDelta: i32 = 0,
};

/// Shop purchases (side panel bee cards).
pub const BuyAction = enum {
    buy_worker_bee,
    buy_swift_bee,
    buy_efficient_bee,
    buy_gardener_bee,
};

/// Handles game actions triggered from the UI.
pub const ActionHandler = struct {
    world: *World,
    resources: *Resources,
    grid: *const Grid,
    textures: *const Textures,

    /// Buy one bee of the given type; beeCountDelta is 0 when unaffordable.
    pub fn handleBuy(self: *@This(), action: BuyAction) !ActionResult {
        var result = ActionResult{};
        const beeType: components.BeeType = switch (action) {
            .buy_worker_bee => .worker,
            .buy_swift_bee => .swift,
            .buy_efficient_bee => .efficient,
            .buy_gardener_bee => .gardener,
        };
        if (self.resources.spendHoney(spawners.BEE_TYPE_COSTS.get(beeType))) {
            _ = try spawners.spawnBeeWithType(self.world, self.grid, self.textures, beeType);
            result.beeCountDelta = 1;
        }
        return result;
    }

    /// Instant Grow: bloom a flower fully (pollen ready) and consume the
    /// growth-boost cooldown. Fired automatically by the game loop.
    pub fn instantGrowFlower(self: *@This(), entity: u32) void {
        if (self.resources.useGrowthBoost()) {
            if (self.world.getFlowerGrowth(entity)) |growth| {
                growth.state = 4;
                growth.hasPollen = true;
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
