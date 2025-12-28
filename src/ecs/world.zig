const std = @import("std");
const rl = @import("raylib");
const Entity = @import("entity.zig").Entity;
const EntityManager = @import("entity.zig").EntityManager;
const INVALID_ENTITY = @import("entity.zig").INVALID_ENTITY;
const components = @import("components.zig");

pub const ComponentIndex = usize;

pub const World = struct {
    entityManager: EntityManager,
    allocator: std.mem.Allocator,

    positions: std.ArrayList(components.Position),
    gridPositions: std.ArrayList(components.GridPosition),
    sprites: std.ArrayList(components.Sprite),
    velocities: std.ArrayList(components.Velocity),
    beeAIs: std.ArrayList(components.BeeAI),
    flowerGrowths: std.ArrayList(components.FlowerGrowth),
    lifespans: std.ArrayList(components.Lifespan),
    pollenCollectors: std.ArrayList(components.PollenCollector),
    scaleSync: std.ArrayList(components.ScaleSync),
    beehives: std.ArrayList(components.Beehive),

    entityToPosition: std.AutoHashMap(Entity, ComponentIndex),
    entityToGridPosition: std.AutoHashMap(Entity, ComponentIndex),
    entityToSprite: std.AutoHashMap(Entity, ComponentIndex),
    entityToVelocity: std.AutoHashMap(Entity, ComponentIndex),
    entityToBeeAI: std.AutoHashMap(Entity, ComponentIndex),
    entityToFlowerGrowth: std.AutoHashMap(Entity, ComponentIndex),
    entityToLifespan: std.AutoHashMap(Entity, ComponentIndex),
    entityToPollenCollector: std.AutoHashMap(Entity, ComponentIndex),
    entityToScaleSync: std.AutoHashMap(Entity, ComponentIndex),
    entityToBeehive: std.AutoHashMap(Entity, ComponentIndex),

    // Flower target count cache - tracks how many bees are targeting each flower
    flowerTargetCount: std.AutoHashMap(Entity, u32),

    entitiesToDestroy: std.ArrayList(Entity),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .entityManager = EntityManager.init(allocator),
            .allocator = allocator,

            .positions = .empty,
            .gridPositions = .empty,
            .sprites = .empty,
            .velocities = .empty,
            .beeAIs = .empty,
            .flowerGrowths = .empty,
            .lifespans = .empty,
            .pollenCollectors = .empty,
            .scaleSync = .empty,
            .beehives = .empty,

            .entityToPosition = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToGridPosition = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToSprite = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToVelocity = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToBeeAI = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToFlowerGrowth = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToLifespan = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToPollenCollector = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToScaleSync = std.AutoHashMap(Entity, ComponentIndex).init(allocator),
            .entityToBeehive = std.AutoHashMap(Entity, ComponentIndex).init(allocator),

            .flowerTargetCount = std.AutoHashMap(Entity, u32).init(allocator),

            .entitiesToDestroy = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.entityManager.deinit();

        self.positions.deinit(self.allocator);
        self.gridPositions.deinit(self.allocator);
        self.sprites.deinit(self.allocator);
        self.velocities.deinit(self.allocator);
        self.beeAIs.deinit(self.allocator);
        self.flowerGrowths.deinit(self.allocator);
        self.lifespans.deinit(self.allocator);
        self.pollenCollectors.deinit(self.allocator);
        self.scaleSync.deinit(self.allocator);
        self.beehives.deinit(self.allocator);

        self.entityToPosition.deinit();
        self.entityToGridPosition.deinit();
        self.entityToSprite.deinit();
        self.entityToVelocity.deinit();
        self.entityToBeeAI.deinit();
        self.entityToFlowerGrowth.deinit();
        self.entityToLifespan.deinit();
        self.entityToPollenCollector.deinit();
        self.entityToScaleSync.deinit();
        self.entityToBeehive.deinit();

        self.flowerTargetCount.deinit();

        self.entitiesToDestroy.deinit(self.allocator);
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
        self.removePosition(entity);
        self.removeGridPosition(entity);
        self.removeSprite(entity);
        self.removeVelocity(entity);
        self.removeBeeAI(entity);
        self.removeFlowerGrowth(entity);
        self.removeLifespan(entity);
        self.removePollenCollector(entity);
        self.removeScaleSync(entity);
        self.removeBeehive(entity);
    }

    pub fn addPosition(self: *@This(), entity: Entity, position: components.Position) !void {
        const index = self.positions.items.len;
        try self.positions.append(self.allocator, position);
        try self.entityToPosition.put(entity, index);
    }

    pub fn getPosition(self: *@This(), entity: Entity) ?*components.Position {
        const index = self.entityToPosition.get(entity) orelse return null;
        return &self.positions.items[index];
    }

    pub fn removePosition(self: *@This(), entity: Entity) void {
        _ = self.entityToPosition.remove(entity);
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

    pub fn addVelocity(self: *@This(), entity: Entity, velocity: components.Velocity) !void {
        const index = self.velocities.items.len;
        try self.velocities.append(self.allocator, velocity);
        try self.entityToVelocity.put(entity, index);
    }

    pub fn getVelocity(self: *@This(), entity: Entity) ?*components.Velocity {
        const index = self.entityToVelocity.get(entity) orelse return null;
        return &self.velocities.items[index];
    }

    pub fn removeVelocity(self: *@This(), entity: Entity) void {
        _ = self.entityToVelocity.remove(entity);
    }

    pub fn addBeeAI(self: *@This(), entity: Entity, beeAI: components.BeeAI) !void {
        const index = self.beeAIs.items.len;
        try self.beeAIs.append(self.allocator, beeAI);
        try self.entityToBeeAI.put(entity, index);
    }

    pub fn getBeeAI(self: *@This(), entity: Entity) ?*components.BeeAI {
        const index = self.entityToBeeAI.get(entity) orelse return null;
        return &self.beeAIs.items[index];
    }

    pub fn removeBeeAI(self: *@This(), entity: Entity) void {
        _ = self.entityToBeeAI.remove(entity);
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

    pub fn addPollenCollector(self: *@This(), entity: Entity, pollenCollector: components.PollenCollector) !void {
        const index = self.pollenCollectors.items.len;
        try self.pollenCollectors.append(self.allocator, pollenCollector);
        try self.entityToPollenCollector.put(entity, index);
    }

    pub fn getPollenCollector(self: *@This(), entity: Entity) ?*components.PollenCollector {
        const index = self.entityToPollenCollector.get(entity) orelse return null;
        return &self.pollenCollectors.items[index];
    }

    pub fn removePollenCollector(self: *@This(), entity: Entity) void {
        _ = self.entityToPollenCollector.remove(entity);
    }

    pub fn addScaleSync(self: *@This(), entity: Entity, scaleSync: components.ScaleSync) !void {
        const index = self.scaleSync.items.len;
        try self.scaleSync.append(self.allocator, scaleSync);
        try self.entityToScaleSync.put(entity, index);
    }

    pub fn getScaleSync(self: *@This(), entity: Entity) ?*components.ScaleSync {
        const index = self.entityToScaleSync.get(entity) orelse return null;
        return &self.scaleSync.items[index];
    }

    pub fn removeScaleSync(self: *@This(), entity: Entity) void {
        _ = self.entityToScaleSync.remove(entity);
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

    pub const QueryIterator = struct {
        entities: []const Entity,
        index: usize,
        allocator: std.mem.Allocator,

        pub fn next(self: *@This()) ?Entity {
            if (self.index >= self.entities.len) {
                return null;
            }
            const entity = self.entities[self.index];
            self.index += 1;
            return entity;
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.entities);
        }
    };

    // Direct iterator for bees - no allocation
    pub const DirectBeeIterator = struct {
        iter: std.AutoHashMap(Entity, ComponentIndex).KeyIterator,
        world: *World,

        pub fn next(self: *@This()) ?Entity {
            while (self.iter.next()) |entity| {
                if (self.world.entityToPosition.contains(entity.*)) {
                    return entity.*;
                }
            }
            return null;
        }
    };

    pub fn iterateBees(self: *@This()) DirectBeeIterator {
        return .{
            .iter = self.entityToBeeAI.keyIterator(),
            .world = self,
        };
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

    // Direct iterator for entities with ScaleSync - no allocation
    pub const DirectScaleSyncIterator = struct {
        iter: std.AutoHashMap(Entity, ComponentIndex).KeyIterator,

        pub fn next(self: *@This()) ?Entity {
            if (self.iter.next()) |entity| {
                return entity.*;
            }
            return null;
        }
    };

    pub fn iterateScaleSyncs(self: *@This()) DirectScaleSyncIterator {
        return .{
            .iter = self.entityToScaleSync.keyIterator(),
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

    pub fn queryEntitiesWithPosition(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToPosition.keyIterator();
        while (iter.next()) |entity| {
            try entities.append(self.allocator, entity.*);
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn queryEntitiesWithBeeAI(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToBeeAI.keyIterator();
        while (iter.next()) |entity| {
            if (self.entityToPosition.contains(entity.*)) {
                try entities.append(self.allocator, entity.*);
            }
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn queryEntitiesWithFlowerGrowth(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToFlowerGrowth.keyIterator();
        while (iter.next()) |entity| {
            if (self.entityToGridPosition.contains(entity.*)) {
                try entities.append(self.allocator, entity.*);
            }
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn queryEntitiesWithLifespan(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToLifespan.keyIterator();
        while (iter.next()) |entity| {
            try entities.append(self.allocator, entity.*);
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn queryEntitiesWithScaleSync(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToScaleSync.keyIterator();
        while (iter.next()) |entity| {
            try entities.append(self.allocator, entity.*);
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }

    pub fn queryEntitiesWithSprite(self: *@This()) !QueryIterator {
        var entities: std.ArrayList(Entity) = .empty;
        var iter = self.entityToSprite.keyIterator();
        while (iter.next()) |entity| {
            if (self.entityToPosition.contains(entity.*) or self.entityToGridPosition.contains(entity.*)) {
                try entities.append(self.allocator, entity.*);
            }
        }
        return QueryIterator{
            .entities = try entities.toOwnedSlice(self.allocator),
            .index = 0,
            .allocator = self.allocator,
        };
    }
};
