const std = @import("std");
const rl = @import("raylib");

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

pub const Velocity = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) @This() {
        return .{ .x = x, .y = y };
    }

    pub fn toVector2(self: @This()) rl.Vector2 {
        return rl.Vector2.init(self.x, self.y);
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
    scatterTimer: f32,
    searchCooldown: f32, // Cooldown before searching for flowers again

    pub fn init() @This() {
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

    pub fn init() @This() {
        const rl_module = @import("raylib");
        return .{
            .state = 0,
            .timeAlive = 0,
            .growthRate = @floatFromInt(rl_module.getRandomValue(1, 10)),
            .growthThreshold = 50,
            .hasPollen = false,
            .pollenCooldown = @floatFromInt(rl_module.getRandomValue(10, 50)),
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

pub const ScaleSync = struct {
    effectiveScale: f32,

    pub fn init(scale: f32) @This() {
        return .{ .effectiveScale = scale };
    }

    pub fn updateFromGrid(self: *@This(), baseScale: f32, gridScale: f32) void {
        self.effectiveScale = baseScale * (gridScale / 3.0);
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
