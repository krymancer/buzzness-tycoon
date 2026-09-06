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
var nextFlowerGen: u64 = 1;

fn takeFlowerGen() u64 {
    const g = nextFlowerGen;
    nextFlowerGen += 1;
    return g;
}

pub const World = struct {
    entityManager: EntityManager,
    allocator: std.mem.Allocator,

    bees: bees.Store,

    gridPositions: std.ArrayList(components.GridPosition),
    freeGridPosition: std.ArrayList(usize) = .empty,
    sprites: std.ArrayList(components.Sprite),
    freeSprite: std.ArrayList(usize) = .empty,
    flowerGrowths: std.ArrayList(components.FlowerGrowth),
    freeFlowerGrowth: std.ArrayList(usize) = .empty,
    lifespans: std.ArrayList(components.Lifespan),
    freeLifespan: std.ArrayList(usize) = .empty,
    beehives: std.ArrayList(components.Beehive),
    freeBeehive: std.ArrayList(usize) = .empty,

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

    /// Bumped whenever the set of flowers (or a flower's footprint) changes,
    /// so the render system can keep its culled, depth-sorted draw list
    /// across frames instead of rebuilding and sorting it every frame.
    /// Globally unique across World instances (a fresh run must not reuse
    /// a value the renderer cached from the previous one).
    flowerGen: u64,

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
            .flowerGen = takeFlowerGen(),
        };
    }

    /// Invalidate cached flower draw order (spawn, removal, SUPER merge,
    /// registry rebuild after a grid shift).
    pub fn markFlowersDirty(self: *@This()) void {
        self.flowerGen = takeFlowerGen();
    }

    pub fn deinit(self: *@This()) void {
        self.entityManager.deinit();
        self.bees.deinit();

        self.gridPositions.deinit(self.allocator);
        self.freeGridPosition.deinit(self.allocator);
        self.sprites.deinit(self.allocator);
        self.freeSprite.deinit(self.allocator);
        self.flowerGrowths.deinit(self.allocator);
        self.freeFlowerGrowth.deinit(self.allocator);
        self.lifespans.deinit(self.allocator);
        self.freeLifespan.deinit(self.allocator);
        self.beehives.deinit(self.allocator);
        self.freeBeehive.deinit(self.allocator);

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
        if (self.entityToGridPosition.get(entity)) |index| {
            self.gridPositions.items[index] = gridPosition;
            self.markFlowersDirty();
            return;
        }
        try self.entityToGridPosition.ensureUnusedCapacity(1);
        // Reserve the free stack before growing storage: removing a component
        // must never allocate, and surviving render-cache slots never move.
        const index = if (self.freeGridPosition.pop()) |slot| blk: {
            self.gridPositions.items[slot] = gridPosition;
            break :blk slot;
        } else blk: {
            try self.freeGridPosition.ensureTotalCapacity(self.allocator, self.gridPositions.items.len + 1);
            const slot = self.gridPositions.items.len;
            try self.gridPositions.append(self.allocator, gridPosition);
            break :blk slot;
        };
        self.entityToGridPosition.putAssumeCapacity(entity, index);
    }

    pub fn getGridPosition(self: *@This(), entity: Entity) ?*components.GridPosition {
        const index = self.entityToGridPosition.get(entity) orelse return null;
        return &self.gridPositions.items[index];
    }

    pub fn removeGridPosition(self: *@This(), entity: Entity) void {
        if (self.entityToGridPosition.fetchRemove(entity)) |entry| {
            self.freeGridPosition.appendAssumeCapacity(entry.value);
            self.markFlowersDirty();
        }
    }

    pub fn addSprite(self: *@This(), entity: Entity, sprite: components.Sprite) !void {
        if (self.entityToSprite.get(entity)) |index| {
            self.sprites.items[index] = sprite;
            self.markFlowersDirty();
            return;
        }
        try self.entityToSprite.ensureUnusedCapacity(1);
        // Reserve the free stack before growing storage: removing a component
        // must never allocate, and surviving render-cache slots never move.
        const index = if (self.freeSprite.pop()) |slot| blk: {
            self.sprites.items[slot] = sprite;
            break :blk slot;
        } else blk: {
            try self.freeSprite.ensureTotalCapacity(self.allocator, self.sprites.items.len + 1);
            const slot = self.sprites.items.len;
            try self.sprites.append(self.allocator, sprite);
            break :blk slot;
        };
        self.entityToSprite.putAssumeCapacity(entity, index);
    }

    pub fn getSprite(self: *@This(), entity: Entity) ?*components.Sprite {
        const index = self.entityToSprite.get(entity) orelse return null;
        return &self.sprites.items[index];
    }

    pub fn removeSprite(self: *@This(), entity: Entity) void {
        if (self.entityToSprite.fetchRemove(entity)) |entry| {
            self.freeSprite.appendAssumeCapacity(entry.value);
            self.markFlowersDirty();
        }
    }

    pub fn addFlowerGrowth(self: *@This(), entity: Entity, flowerGrowth: components.FlowerGrowth) !void {
        if (self.entityToFlowerGrowth.get(entity)) |index| {
            self.flowerGrowths.items[index] = flowerGrowth;
            self.markFlowersDirty();
            return;
        }
        try self.entityToFlowerGrowth.ensureUnusedCapacity(1);
        // Reserve the free stack before growing storage: removing a component
        // must never allocate, and surviving render-cache slots never move.
        const index = if (self.freeFlowerGrowth.pop()) |slot| blk: {
            self.flowerGrowths.items[slot] = flowerGrowth;
            break :blk slot;
        } else blk: {
            try self.freeFlowerGrowth.ensureTotalCapacity(self.allocator, self.flowerGrowths.items.len + 1);
            const slot = self.flowerGrowths.items.len;
            try self.flowerGrowths.append(self.allocator, flowerGrowth);
            break :blk slot;
        };
        self.entityToFlowerGrowth.putAssumeCapacity(entity, index);
        self.markFlowersDirty();
    }

    pub fn getFlowerGrowth(self: *@This(), entity: Entity) ?*components.FlowerGrowth {
        const index = self.entityToFlowerGrowth.get(entity) orelse return null;
        return &self.flowerGrowths.items[index];
    }

    pub fn removeFlowerGrowth(self: *@This(), entity: Entity) void {
        if (self.entityToFlowerGrowth.fetchRemove(entity)) |entry| {
            self.freeFlowerGrowth.appendAssumeCapacity(entry.value);
            self.markFlowersDirty();
        }
    }

    pub fn addLifespan(self: *@This(), entity: Entity, lifespan: components.Lifespan) !void {
        if (self.entityToLifespan.get(entity)) |index| {
            self.lifespans.items[index] = lifespan;
            self.markFlowersDirty();
            return;
        }
        try self.entityToLifespan.ensureUnusedCapacity(1);
        // Reserve the free stack before growing storage: removing a component
        // must never allocate, and surviving render-cache slots never move.
        const index = if (self.freeLifespan.pop()) |slot| blk: {
            self.lifespans.items[slot] = lifespan;
            break :blk slot;
        } else blk: {
            try self.freeLifespan.ensureTotalCapacity(self.allocator, self.lifespans.items.len + 1);
            const slot = self.lifespans.items.len;
            try self.lifespans.append(self.allocator, lifespan);
            break :blk slot;
        };
        self.entityToLifespan.putAssumeCapacity(entity, index);
    }

    pub fn getLifespan(self: *@This(), entity: Entity) ?*components.Lifespan {
        const index = self.entityToLifespan.get(entity) orelse return null;
        return &self.lifespans.items[index];
    }

    pub fn removeLifespan(self: *@This(), entity: Entity) void {
        if (self.entityToLifespan.fetchRemove(entity)) |entry| {
            self.freeLifespan.appendAssumeCapacity(entry.value);
            self.markFlowersDirty();
        }
    }

    pub fn addBeehive(self: *@This(), entity: Entity, beehive: components.Beehive) !void {
        if (self.entityToBeehive.get(entity)) |index| {
            self.beehives.items[index] = beehive;
            self.markFlowersDirty();
            return;
        }
        try self.entityToBeehive.ensureUnusedCapacity(1);
        // Reserve the free stack before growing storage: removing a component
        // must never allocate, and surviving render-cache slots never move.
        const index = if (self.freeBeehive.pop()) |slot| blk: {
            self.beehives.items[slot] = beehive;
            break :blk slot;
        } else blk: {
            try self.freeBeehive.ensureTotalCapacity(self.allocator, self.beehives.items.len + 1);
            const slot = self.beehives.items.len;
            try self.beehives.append(self.allocator, beehive);
            break :blk slot;
        };
        self.entityToBeehive.putAssumeCapacity(entity, index);
    }

    pub fn getBeehive(self: *@This(), entity: Entity) ?*components.Beehive {
        const index = self.entityToBeehive.get(entity) orelse return null;
        return &self.beehives.items[index];
    }

    pub fn removeBeehive(self: *@This(), entity: Entity) void {
        if (self.entityToBeehive.fetchRemove(entity)) |entry| {
            self.freeBeehive.appendAssumeCapacity(entry.value);
            self.markFlowersDirty();
        }
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
        self.markFlowersDirty();
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

test "flower turnover reuses component slots without moving surviving flowers" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    const survivor = try world.createEntity();
    try world.addGridPosition(survivor, components.GridPosition.init(2, 3));
    try world.addFlowerGrowth(survivor, components.FlowerGrowth.init(.rose));
    const slot = world.entityToFlowerGrowth.get(survivor).?;
    const dummy = rl.Texture{ .id = 0, .width = 32, .height = 32, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    for (0..200) |_| {
        const e = try world.createEntity();
        try world.addGridPosition(e, components.GridPosition.init(4, 5));
        try world.addSprite(e, components.Sprite.init(dummy, 32, 32, 2));
        try world.addFlowerGrowth(e, components.FlowerGrowth.init(.tulip));
        try world.addLifespan(e, components.Lifespan.init(30));
        const before = world.flowerGen;
        try world.destroyEntity(e);
        try world.processDestroyQueue();
        try std.testing.expect(world.flowerGen != before);
        try std.testing.expectEqual(slot, world.entityToFlowerGrowth.get(survivor).?);
        try std.testing.expectEqual(components.FlowerType.rose, world.flowerGrowths.items[slot].flowerType);
    }
    try std.testing.expect(world.gridPositions.items.len <= 2);
    try std.testing.expect(world.flowerGrowths.items.len <= 2);
    try std.testing.expect(world.sprites.items.len <= 1);
    try std.testing.expect(world.lifespans.items.len <= 1);
}
