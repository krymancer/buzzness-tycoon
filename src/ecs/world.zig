const std = @import("std");
const rl = @import("raylib");
const Entity = @import("entity.zig").Entity;
const EntityManager = @import("entity.zig").EntityManager;
const INVALID_ENTITY = @import("entity.zig").INVALID_ENTITY;
const components = @import("components.zig");
const bees = @import("../bees.zig");

pub const ComponentIndex = usize;

// Key for grid position lookups - packed i32 pair
pub const GridKey = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) @This() {
        return .{ .x = x, .y = y };
    }
};

/// Entity/component storage for the meadow (flowers, the hive) plus the
/// dense bee store. Bees are not entities — see bees.zig.
pub const World = struct {
    entityManager: EntityManager,
    allocator: std.mem.Allocator,

    bees: bees.Store,

    gridPositions: std.ArrayList(components.GridPosition),
    sprites: std.ArrayList(components.Sprite),
    flowerGrowths: std.ArrayList(components.FlowerGrowth),
    lifespans: std.ArrayList(components.Lifespan),
    beehives: std.ArrayList(components.Beehive),

    entityToGridPosition: std.AutoHashMap(Entity, ComponentIndex),
    entityToSprite: std.AutoHashMap(Entity, ComponentIndex),
    entityToFlowerGrowth: std.AutoHashMap(Entity, ComponentIndex),
    entityToLifespan: std.AutoHashMap(Entity, ComponentIndex),
    entityToBeehive: std.AutoHashMap(Entity, ComponentIndex),

    // Flower target count cache - tracks how many bees are targeting each flower
    flowerTargetCount: std.AutoHashMap(Entity, u32),

    // Grid position to flower entity lookup - O(1) spatial queries
    gridPosToFlower: std.AutoHashMap(GridKey, Entity),

    entitiesToDestroy: std.ArrayList(Entity),

    pub fn init(allocator: std.mem.Allocator) @This() {
        var entityToGridPosition = std.AutoHashMap(Entity, ComponentIndex).init(allocator);
        var entityToSprite = std.AutoHashMap(Entity, ComponentIndex).init(allocator);
        var entityToFlowerGrowth = std.AutoHashMap(Entity, ComponentIndex).init(allocator);
        var entityToLifespan = std.AutoHashMap(Entity, ComponentIndex).init(allocator);
        const entityToBeehive = std.AutoHashMap(Entity, ComponentIndex).init(allocator);
        var flowerTargetCount_ = std.AutoHashMap(Entity, u32).init(allocator);
        var gridPosToFlower_ = std.AutoHashMap(GridKey, Entity).init(allocator);

        // Pre-allocate for a well-grown meadow to avoid runtime resizing.
        entityToSprite.ensureTotalCapacity(4096) catch {};
        entityToLifespan.ensureTotalCapacity(4096) catch {};
        entityToGridPosition.ensureTotalCapacity(4096) catch {};
        entityToFlowerGrowth.ensureTotalCapacity(4096) catch {};
        flowerTargetCount_.ensureTotalCapacity(4096) catch {};
        gridPosToFlower_.ensureTotalCapacity(4096) catch {};

        return .{
            .entityManager = EntityManager.init(allocator),
            .allocator = allocator,

            .bees = bees.Store.init(allocator),

            .gridPositions = .empty,
            .sprites = .empty,
            .flowerGrowths = .empty,
            .lifespans = .empty,
            .beehives = .empty,

            .entityToGridPosition = entityToGridPosition,
            .entityToSprite = entityToSprite,
            .entityToFlowerGrowth = entityToFlowerGrowth,
            .entityToLifespan = entityToLifespan,
            .entityToBeehive = entityToBeehive,

            .flowerTargetCount = flowerTargetCount_,

            .gridPosToFlower = gridPosToFlower_,

            .entitiesToDestroy = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.entityManager.deinit();
        self.bees.deinit();

        self.gridPositions.deinit(self.allocator);
        self.sprites.deinit(self.allocator);
        self.flowerGrowths.deinit(self.allocator);
        self.lifespans.deinit(self.allocator);
        self.beehives.deinit(self.allocator);

        self.entityToGridPosition.deinit();
        self.entityToSprite.deinit();
        self.entityToFlowerGrowth.deinit();
        self.entityToLifespan.deinit();
        self.entityToBeehive.deinit();

        self.flowerTargetCount.deinit();

        self.gridPosToFlower.deinit();

        self.entitiesToDestroy.deinit(self.allocator);
    }

    /// Re-proportion the simulated bees to the colony (see bees.Store).
    pub fn rebalanceBees(self: *@This()) !void {
        try self.bees.rebalance(self);
    }

    pub fn createEntity(self: *@This()) !Entity {
        return try self.entityManager.create();
    }

    pub fn destroyEntity(self: *@This(), entity: Entity) !void {
        try self.entitiesToDestroy.append(self.allocator, entity);
    }

    pub fn processDestroyQueue(self: *@This()) !void {
        for (self.entitiesToDestroy.items) |entity| {
            try self.removeAllComponents(entity);
            try self.entityManager.destroy(entity);
        }
        self.entitiesToDestroy.clearRetainingCapacity();
    }

    fn removeAllComponents(self: *@This(), entity: Entity) !void {
        self.removeGridPosition(entity);
        self.removeSprite(entity);
        self.removeFlowerGrowth(entity);
        self.removeLifespan(entity);
        self.removeBeehive(entity);
    }

    pub fn addGridPosition(self: *@This(), entity: Entity, gridPosition: components.GridPosition) !void {
        const index = self.gridPositions.items.len;
        try self.gridPositions.append(self.allocator, gridPosition);
        try self.entityToGridPosition.put(entity, index);
    }

    pub fn getGridPosition(self: *@This(), entity: Entity) ?*components.GridPosition {
        const index = self.entityToGridPosition.get(entity) orelse return null;
        return &self.gridPositions.items[index];
    }

    pub fn removeGridPosition(self: *@This(), entity: Entity) void {
        _ = self.entityToGridPosition.remove(entity);
    }

    pub fn addSprite(self: *@This(), entity: Entity, sprite: components.Sprite) !void {
        const index = self.sprites.items.len;
        try self.sprites.append(self.allocator, sprite);
        try self.entityToSprite.put(entity, index);
    }

    pub fn getSprite(self: *@This(), entity: Entity) ?*components.Sprite {
        const index = self.entityToSprite.get(entity) orelse return null;
        return &self.sprites.items[index];
    }

    pub fn removeSprite(self: *@This(), entity: Entity) void {
        _ = self.entityToSprite.remove(entity);
    }

    pub fn addFlowerGrowth(self: *@This(), entity: Entity, flowerGrowth: components.FlowerGrowth) !void {
        const index = self.flowerGrowths.items.len;
        try self.flowerGrowths.append(self.allocator, flowerGrowth);
        try self.entityToFlowerGrowth.put(entity, index);
    }

    pub fn getFlowerGrowth(self: *@This(), entity: Entity) ?*components.FlowerGrowth {
        const index = self.entityToFlowerGrowth.get(entity) orelse return null;
        return &self.flowerGrowths.items[index];
    }

    pub fn removeFlowerGrowth(self: *@This(), entity: Entity) void {
        _ = self.entityToFlowerGrowth.remove(entity);
    }

    pub fn addLifespan(self: *@This(), entity: Entity, lifespan: components.Lifespan) !void {
        const index = self.lifespans.items.len;
        try self.lifespans.append(self.allocator, lifespan);
        try self.entityToLifespan.put(entity, index);
    }

    pub fn getLifespan(self: *@This(), entity: Entity) ?*components.Lifespan {
        const index = self.entityToLifespan.get(entity) orelse return null;
        return &self.lifespans.items[index];
    }

    pub fn removeLifespan(self: *@This(), entity: Entity) void {
        _ = self.entityToLifespan.remove(entity);
    }

    pub fn addBeehive(self: *@This(), entity: Entity, beehive: components.Beehive) !void {
        const index = self.beehives.items.len;
        try self.beehives.append(self.allocator, beehive);
        try self.entityToBeehive.put(entity, index);
    }

    pub fn getBeehive(self: *@This(), entity: Entity) ?*components.Beehive {
        const index = self.entityToBeehive.get(entity) orelse return null;
        return &self.beehives.items[index];
    }

    pub fn removeBeehive(self: *@This(), entity: Entity) void {
        _ = self.entityToBeehive.remove(entity);
    }

    // Direct iterator for flowers - no allocation
    pub const DirectFlowerIterator = struct {
        iter: std.AutoHashMap(Entity, ComponentIndex).KeyIterator,
        world: *World,

        pub fn next(self: *@This()) ?Entity {
            while (self.iter.next()) |entity| {
                if (self.world.entityToGridPosition.contains(entity.*)) {
                    return entity.*;
                }
            }
            return null;
        }
    };

    pub fn iterateFlowers(self: *@This()) DirectFlowerIterator {
        return .{
            .iter = self.entityToFlowerGrowth.keyIterator(),
            .world = self,
        };
    }

    // Direct iterator for entities with Lifespan - no allocation
    pub const DirectLifespanIterator = struct {
        iter: std.AutoHashMap(Entity, ComponentIndex).KeyIterator,

        pub fn next(self: *@This()) ?Entity {
            if (self.iter.next()) |entity| {
                return entity.*;
            }
            return null;
        }
    };

    pub fn iterateLifespans(self: *@This()) DirectLifespanIterator {
        return .{
            .iter = self.entityToLifespan.keyIterator(),
        };
    }

    // Flower target count helpers - O(1) tracking of how many bees target each flower
    pub fn incrementFlowerTarget(self: *@This(), flowerEntity: Entity) void {
        const current = self.flowerTargetCount.get(flowerEntity) orelse 0;
        self.flowerTargetCount.put(flowerEntity, current + 1) catch {};
    }

    pub fn decrementFlowerTarget(self: *@This(), flowerEntity: Entity) void {
        const current = self.flowerTargetCount.get(flowerEntity) orelse 0;
        if (current > 0) {
            self.flowerTargetCount.put(flowerEntity, current - 1) catch {};
        }
    }

    pub fn getFlowerTargetCount(self: *@This(), flowerEntity: Entity) u32 {
        return self.flowerTargetCount.get(flowerEntity) orelse 0;
    }

    pub fn clearFlowerTargetCount(self: *@This(), flowerEntity: Entity) void {
        _ = self.flowerTargetCount.remove(flowerEntity);
    }

    // Grid position to flower helpers - O(1) spatial lookup for flowers
    pub fn registerFlowerAtGrid(self: *@This(), gridX: i32, gridY: i32, flowerEntity: Entity) void {
        self.gridPosToFlower.put(GridKey.init(gridX, gridY), flowerEntity) catch {};
    }

    pub fn unregisterFlowerAtGrid(self: *@This(), gridX: i32, gridY: i32) void {
        _ = self.gridPosToFlower.remove(GridKey.init(gridX, gridY));
    }

    pub fn getFlowerAtGrid(self: *@This(), gridX: i32, gridY: i32) ?Entity {
        return self.gridPosToFlower.get(GridKey.init(gridX, gridY));
    }

    pub fn hasFlowerAtGrid(self: *@This(), gridX: i32, gridY: i32) bool {
        return self.gridPosToFlower.contains(GridKey.init(gridX, gridY));
    }

    /// Rebuild the grid→flower registry from the entities' current grid
    /// positions. Needed after bulk position shifts (grid expansion), where
    /// the registry's integer keys would otherwise go stale. SUPER flowers
    /// re-claim their whole 2x2 block.
    pub fn rebuildFlowerRegistry(self: *@This()) void {
        self.gridPosToFlower.clearRetainingCapacity();
        var iter = self.iterateFlowers();
        while (iter.next()) |entity| {
            const gridPos = self.getGridPosition(entity) orelse continue;
            const gridX: i32 = @intFromFloat(@floor(gridPos.x));
            const gridY: i32 = @intFromFloat(@floor(gridPos.y));
            self.registerFlowerAtGrid(gridX, gridY, entity);
            if (self.getFlowerGrowth(entity)) |growth| {
                if (growth.isSuper) {
                    self.registerFlowerAtGrid(gridX + 1, gridY, entity);
                    self.registerFlowerAtGrid(gridX, gridY + 1, entity);
                    self.registerFlowerAtGrid(gridX + 1, gridY + 1, entity);
                }
            }
        }
    }
};
