const std = @import("std");
const rl = @import("raylib");
const theme = @import("../theme.zig");

pub const Position = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) @This() {
        return .{ .x = x, .y = y };
    }

    pub fn toVector2(self: @This()) rl.Vector2 {
        return rl.Vector2.init(self.x, self.y);
    }

    pub fn fromVector2(vec: rl.Vector2) @This() {
        return .{ .x = vec.x, .y = vec.y };
    }
};

pub const GridPosition = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) @This() {
        return .{ .x = x, .y = y };
    }

    pub fn toVector2(self: @This()) rl.Vector2 {
        return rl.Vector2.init(self.x, self.y);
    }
};

pub const Sprite = struct {
    texture: rl.Texture,
    width: f32,
    height: f32,
    scale: f32,

    pub fn init(texture: rl.Texture, width: f32, height: f32, scale: f32) @This() {
        return .{
            .texture = texture,
            .width = width,
            .height = height,
            .scale = scale,
        };
    }
};

pub const BeeAI = struct {
    targetEntity: ?u32,
    targetLocked: bool,
    carryingPollen: bool,
    wanderAngle: f32,
    wanderChangeTimer: f32,
    lastGridX: i32,
    lastGridY: i32,
    // Last cell checked for composting (separate from lastGridX/Y so the
    // planting pass still sees "new cell" transitions).
    lastCompostX: i32 = -1,
    lastCompostY: i32 = -1,
    scatterTimer: f32,
    searchCooldown: f32,
    beeType: BeeType,
    // Seed Scouts: the locked target is an empty tile to plant (targetEntity
    // is null; targetGridX/Y hold the cell).
    sowTarget: bool = false,
    // Saddlebags: flowers collected on the current trip. The bee only
    // heads home (carryingPollen) once this reaches the bag capacity.
    tripLoads: u8 = 0,
    // Cached target grid coords — lets the stagger-skip path compute world pos
    // without a HashMap lookup. Invalid when targetLocked == false.
    targetGridX: f32,
    targetGridY: f32,

    pub fn init() @This() {
        return initWithType(.worker);
    }

    pub fn initWithType(beeType: BeeType) @This() {
        const rl_module = @import("raylib");
        return .{
            .targetEntity = null,
            .targetLocked = false,
            .carryingPollen = false,
            .wanderAngle = @as(f32, @floatFromInt(rl_module.getRandomValue(0, 360))) * std.math.pi / 180.0,
            .wanderChangeTimer = 0,
            .lastGridX = -1,
            .lastGridY = -1,
            .scatterTimer = 0,
            .searchCooldown = 0,
            .beeType = beeType,
            .targetGridX = 0,
            .targetGridY = 0,
        };
    }
};

pub const FlowerType = enum {
    rose,
    tulip,
    dandelion,

    /// What sets the types apart (#71). Dandelion is the cheap, quick,
    /// short-lived filler; tulip the slow, rich, lasting investment; rose
    /// the baseline. SUPER merging still needs four of a kind, so the
    /// choice is "commit to a type", not just "pick the best".
    pub const Stats = struct {
        /// Planting price in honey.
        plantCost: f32,
        /// Pollen per collection (FlowerGrowth.pollenMultiplier).
        pollenMul: f32,
        /// Maturing / pollen-regrow speed (scales FlowerGrowth.growthRate).
        growthMul: f32,
        /// Lifespan (scales the 60-120 s base).
        lifespanMul: f32,
    };

    pub fn stats(self: @This()) Stats {
        return switch (self) {
            .dandelion => .{ .plantCost = 5, .pollenMul = 0.7, .growthMul = 1.3, .lifespanMul = 0.7 },
            .rose => .{ .plantCost = 10, .pollenMul = 1.0, .growthMul = 1.0, .lifespanMul = 1.0 },
            .tulip => .{ .plantCost = 25, .pollenMul = 1.6, .growthMul = 0.75, .lifespanMul = 1.4 },
        };
    }
};

pub const BeeType = enum {
    worker, // Default, baseline stats
    swift, // 2x movement speed
    efficient, // 2x faster pollen collection
    gardener, // Can spawn flowers

    pub fn getSpeedMultiplier(self: @This()) f32 {
        return switch (self) {
            .worker => 1.0,
            .swift => 2.0,
            .efficient => 1.0,
            .gardener => 1.0,
        };
    }

    pub fn getCollectionMultiplier(self: @This()) f32 {
        return switch (self) {
            .worker => 1.0,
            .swift => 1.0,
            .efficient => 2.0,
            .gardener => 1.0,
        };
    }

    pub fn canSpawnFlowers(self: @This()) bool {
        return self == .gardener;
    }

    pub fn getColor(self: @This()) rl.Color {
        return switch (self) {
            .worker => theme.CatppuccinMocha.Color.text,
            .swift => theme.CatppuccinMocha.Color.blue,
            .efficient => theme.CatppuccinMocha.Color.green,
            .gardener => theme.CatppuccinMocha.Color.pink,
        };
    }
};

pub const FlowerGrowth = struct {
    state: f32,
    timeAlive: f32,
    growthRate: f32,
    growthThreshold: f32,
    hasPollen: bool,
    pollenCooldown: f32,
    pollenMultiplier: f32,
    flowerType: FlowerType,
    // SUPER flower: a 2x2 block of same-type flowers merged into one plant.
    // The entity sits at the block's top-left (anchor) cell but owns all four
    // cells in the grid registry, renders at double scale over the block, and
    // yields double the four singles' combined pollen (8x a lone flower).
    isSuper: bool = false,
    // Rotten: the flower reached the end of its life and withered in place.
    // It yields no pollen and blocks its cell until the player clears it.
    isRotten: bool = false,

    pub fn init(flowerType: FlowerType) @This() {
        const rl_module = @import("raylib");
        const stats = flowerType.stats();
        return .{
            .state = 0,
            .timeAlive = 0,
            .growthRate = @as(f32, @floatFromInt(rl_module.getRandomValue(1, 10))) * stats.growthMul,
            // Bloom a bit faster and refill pollen ~2-3x sooner so a bee swarm
            // stays fed and honey actually accumulates toward the late tree.
            .growthThreshold = 35,
            .hasPollen = false,
            .pollenCooldown = @floatFromInt(rl_module.getRandomValue(5, 16)),
            .pollenMultiplier = stats.pollenMul,
            .flowerType = flowerType,
        };
    }
};

pub const Lifespan = struct {
    timeAlive: f32,
    totalTimeAlive: f32,
    timeSpan: f32,

    pub fn init(timeSpan: f32) @This() {
        return .{
            .timeAlive = 0,
            .totalTimeAlive = 0,
            .timeSpan = timeSpan,
        };
    }

    pub fn isDead(self: @This()) bool {
        return self.totalTimeAlive >= self.timeSpan;
    }
};

pub const PollenCollector = struct {
    pollenCollected: f32,

    pub fn init() @This() {
        return .{ .pollenCollected = 0 };
    }

    pub fn collect(self: *@This(), amount: f32) void {
        self.pollenCollected += amount;
    }
};

pub const Beehive = struct {
    honeyConversionFactor: f32,

    pub fn init() @This() {
        return .{
            .honeyConversionFactor = 1.0,
        };
    }
};

/// Tracks dying flowers that can be saved with a rebirth bubble
pub const RebirthBubble = struct {
    timeRemaining: f32, // Time left to click the bubble
    wasClicked: bool, // Flag to mark bubble was clicked

    // How long the bubble appears before flower dies
    pub const BUBBLE_DURATION: f32 = 5.0;
    // How close to death the flower must be for bubble to appear
    pub const DEATH_THRESHOLD: f32 = 5.0;

    pub fn init() @This() {
        return .{
            .timeRemaining = BUBBLE_DURATION,
            .wasClicked = false,
        };
    }
};
