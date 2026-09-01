const rl = @import("raylib");
const std = @import("std");
const config = @import("config.zig");

pub const Resources = struct {
    honey: f32,
    honeyCapacity: f32,
    storageLevel: u32,

    // Rolling honey/sec tracker (EMA over 1s windows)
    honeyPerSec: f32,
    honeyThisSecond: f32,
    rateWindowTimer: f32,

    // Growth boost ability
    growthBoostCooldown: f32, // Current cooldown remaining
    growthBoostMaxCooldown: f32, // Max cooldown (can be upgraded)
    growthBoostLevel: u32,

    /// Successful spends so far this session; lets the game notice a
    /// purchase even when bees refill the storage in the same frame.
    spendCount: u32,

    // Storage upgrade costs: 50, 100, 200, 400, 800...
    const BASE_STORAGE_COST: f32 = 50.0;
    const BASE_CAPACITY: f32 = 500.0;
    const CAPACITY_PER_LEVEL: f32 = 500.0;

    // Growth boost upgrade
    const BASE_GROWTH_COOLDOWN: f32 = 10.0; // 10 seconds base cooldown
    const COOLDOWN_REDUCTION_PER_LEVEL: f32 = 1.5; // -1.5s per level
    const MIN_COOLDOWN: f32 = 2.0; // Minimum 2 second cooldown
    const BASE_GROWTH_UPGRADE_COST: f32 = 30.0;

    pub fn init() @This() {
        return .{
            .honey = config.starting_honey,
            .honeyCapacity = BASE_CAPACITY,
            .storageLevel = 1,
            .honeyPerSec = 0,
            .honeyThisSecond = 0,
            .rateWindowTimer = 0,
            .growthBoostCooldown = 0,
            .growthBoostMaxCooldown = BASE_GROWTH_COOLDOWN,
            .growthBoostLevel = 1,
            .spendCount = 0,
        };
    }

    pub fn addHoney(self: *@This(), amount: f32) void {
        if (config.honey_cap_enabled) {
            self.honey = @min(self.honey + amount, self.honeyCapacity);
        } else {
            self.honey += amount;
        }
        self.honeyThisSecond += amount;
    }

    pub fn tickRate(self: *@This(), deltaTime: f32) void {
        self.rateWindowTimer += deltaTime;
        if (self.rateWindowTimer >= 1.0) {
            // EMA smoothing: 60% new, 40% prior
            self.honeyPerSec = self.honeyPerSec * 0.4 + self.honeyThisSecond * 0.6;
            self.honeyThisSecond = 0;
            self.rateWindowTimer = 0;
        }
    }

    pub fn spendHoney(self: *@This(), amount: f32) bool {
        if (self.honey >= amount) {
            // A run past the f32 economy holds inf honey (#64), and an
            // inf-priced upgrade would leave inf - inf = NaN behind, which
            // fails every later comparison. An infinite stockpile stays
            // infinite instead.
            const left = self.honey - amount;
            self.honey = if (std.math.isNan(left)) self.honey else left;
            if (amount > 0) self.spendCount +%= 1;
            return true;
        }
        return false;
    }

    pub fn getCapacityPercent(self: *const @This()) f32 {
        if (!config.honey_cap_enabled) return 0;
        return self.honey / self.honeyCapacity;
    }

    pub fn isAtCapacity(self: *const @This()) bool {
        if (!config.honey_cap_enabled) return false;
        return self.honey >= self.honeyCapacity;
    }

    // Growth boost methods
    pub fn updateCooldown(self: *@This(), deltaTime: f32) void {
        if (self.growthBoostCooldown > 0) {
            self.growthBoostCooldown = @max(0, self.growthBoostCooldown - deltaTime);
        }
    }

    pub fn canUseGrowthBoost(self: *const @This()) bool {
        return self.growthBoostCooldown <= 0;
    }

    pub fn useGrowthBoost(self: *@This()) bool {
        if (self.canUseGrowthBoost()) {
            self.growthBoostCooldown = self.growthBoostMaxCooldown;
            return true;
        }
        return false;
    }

    pub fn getCooldownPercent(self: *const @This()) f32 {
        if (self.growthBoostMaxCooldown <= 0) return 0;
        return self.growthBoostCooldown / self.growthBoostMaxCooldown;
    }
};
