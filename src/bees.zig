//! Dense bee storage and colony ("cohort") bookkeeping.
//!
//! Bees are not ECS entities: nothing ever refers to a bee by id, every bee
//! carries the same handful of fields, and the simulation touches all of
//! them every frame. Keeping them in one `MultiArrayList` (struct-of-arrays)
//! makes the per-frame work a linear sweep with no hash lookups.
//!
//! Above `SIM_CAP` the colony is simulated by representatives: the store
//! tracks the true population per type, simulates at most `SIM_CAP` bees
//! and keeps the simulated mix proportional to the population (with at
//! least one representative of every owned type). The surplus is dormant —
//! counted, saved and shown in the HUD, never iterated.
//!
//! Honey stays exact this way: income is bounded by flower pollen, not by
//! bee count. Every flower with pollen accepts at most `MAX_BEES_PER_FLOWER`
//! claims, so once the simulated swarm can fill every claim slot (the cap is
//! well above the largest meadow's slot count), extra bees add nothing in
//! the per-bee sim either. Scaling a representative's pollen delivery by
//! `population / simulated` — the obvious "virtual bee" scheme — would have
//! multiplied late-game income by that factor instead.

const std = @import("std");
const rl = @import("raylib");
const components = @import("ecs/components.zig");
const World = @import("ecs/world.zig").World;
const utils = @import("utils.zig");
const save = @import("save.zig");
const spawners = @import("spawners.zig");

pub const BeeType = components.BeeType;
pub const TYPE_COUNT: usize = 4;

/// Most bees simulated individually. Must exceed the claim slots of the
/// largest meadow (127x127 cells x 3 bees per flower ≈ 48k) so a saturated
/// colony behaves exactly like the per-bee sim would.
pub const SIM_CAP: usize = 50_000;

/// Population ceiling per type (also the save-file bound).
pub const MAX_PER_TYPE: u32 = save.MAX_BEES_PER_TYPE;

pub const Bee = struct {
    pos: components.Position,
    ai: components.BeeAI,
    collector: components.PollenCollector,
    life: components.Lifespan,
};

/// Where a bee just died, for the renderer's fading puff. Screen-space like
/// bee positions and carried along by `translate`. A fixed ring: when many
/// bees die in one frame only the last few puffs survive, which is plenty.
pub const DeathPuff = struct { x: f32, y: f32, age: f32 };
pub const PUFF_LIFETIME: f32 = 0.6;
pub const MAX_PUFFS: usize = 64;

/// Screen-space extents of the meadow, for placing new representatives.
/// Mirrors `Grid`'s pan/zoom state; refreshed by spawners and by the bee
/// system every frame so late-spawned bees land on the field.
pub const Meadow = struct {
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    scale: f32 = 1,
    width: usize = 17,
    height: usize = 17,

    /// Random point on a random tile (same distribution the grid used).
    pub fn randomPos(self: Meadow) rl.Vector2 {
        const i = rl.getRandomValue(0, @as(i32, @intCast(self.width - 1)));
        const j = rl.getRandomValue(0, @as(i32, @intCast(self.height - 1)));
        const tile = utils.isoToXY(@floatFromInt(i), @floatFromInt(j), 32, 32, self.offset.x, self.offset.y, self.scale);
        const span: i32 = @intFromFloat(32 * self.scale);
        const dx: f32 = @floatFromInt(rl.getRandomValue(0, span));
        const dy: f32 = @floatFromInt(rl.getRandomValue(0, span));
        return rl.Vector2.init(tile.x + dx, tile.y + dy);
    }
};

/// Split `cap` representatives across types in proportion to `population`
/// (largest-remainder rounding). Every owned type keeps at least one
/// representative so a lone gardener still plants. Populations at or under
/// the cap are simulated in full.
pub fn apportion(population: [TYPE_COUNT]u32, cap: u32) [TYPE_COUNT]u32 {
    var total: u64 = 0;
    for (population) |p| total += p;
    if (total <= cap) return population;

    var out: [TYPE_COUNT]u32 = undefined;
    var remainder: [TYPE_COUNT]u64 = undefined;
    var assigned: u64 = 0;
    for (population, 0..) |p, i| {
        const exact: u64 = @as(u64, p) * cap;
        out[i] = @intCast(exact / total);
        remainder[i] = exact % total;
        assigned += out[i];
    }
    while (assigned < cap) : (assigned += 1) {
        var best: usize = 0;
        for (remainder, 0..) |r, i| {
            if (r > remainder[best]) best = i;
        }
        out[best] += 1;
        remainder[best] = 0;
    }
    // Minimum-one guarantee, paid for by the best-represented type.
    for (0..TYPE_COUNT) |i| {
        if (population[i] == 0 or out[i] > 0) continue;
        var donor: usize = 0;
        for (out, 0..) |n, j| {
            if (n > out[donor]) donor = j;
        }
        if (out[donor] > 1) {
            out[donor] -= 1;
            out[i] = 1;
        }
    }
    return out;
}

pub const Store = struct {
    allocator: std.mem.Allocator,
    list: std.MultiArrayList(Bee) = .empty,
    /// True colony size per type (simulated + dormant).
    population: [TYPE_COUNT]u32 = @splat(0),
    /// Simulated bees per type; sums to `list.len`.
    simulated: [TYPE_COUNT]u32 = @splat(0),
    /// Set when the population changed without the simulated mix following
    /// (purchases past the cap, deaths); cleared by `rebalance`.
    needsRebalance: bool = false,
    meadow: Meadow = .{},
    /// Recent deaths (all slots start expired). See DeathPuff.
    puffs: [MAX_PUFFS]DeathPuff = @splat(.{ .x = 0, .y = 0, .age = PUFF_LIFETIME }),
    puffNext: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Store) void {
        self.list.deinit(self.allocator);
    }

    /// Colony size across all types.
    pub fn total(self: *const Store) u64 {
        var n: u64 = 0;
        for (self.population) |p| n += p;
        return n;
    }

    pub fn count(self: *const Store, beeType: BeeType) u32 {
        return self.population[@intFromEnum(beeType)];
    }

    /// Bees in the colony that are not simulated.
    pub fn dormant(self: *const Store) u64 {
        return self.total() - self.list.len;
    }

    /// How many colony bees each simulated bee of `beeType` stands for.
    pub fn weight(self: *const Store, beeType: BeeType) f32 {
        const t = @intFromEnum(beeType);
        if (self.simulated[t] == 0) return 1.0;
        return @as(f32, @floatFromInt(self.population[t])) / @as(f32, @floatFromInt(self.simulated[t]));
    }

    /// Add one bee to the colony. It is simulated right away while the cap
    /// has room; past it the bee joins the dormant surplus and the mix is
    /// re-proportioned on the next `rebalance`. False at the type ceiling.
    pub fn add(self: *Store, beeType: BeeType) !bool {
        const t = @intFromEnum(beeType);
        if (self.population[t] >= MAX_PER_TYPE) return false;
        self.population[t] += 1;
        if (self.list.len < SIM_CAP) {
            _ = try self.spawnSimulated(beeType, self.meadow.randomPos());
        } else {
            self.needsRebalance = true;
        }
        return true;
    }

    /// Place a simulated bee without touching the population (loading).
    /// Returns its index.
    pub fn spawnSimulated(self: *Store, beeType: BeeType, pos: rl.Vector2) !usize {
        const index = self.list.len;
        try self.list.append(self.allocator, .{
            .pos = components.Position.fromVector2(pos),
            .ai = components.BeeAI.initWithType(beeType),
            .collector = components.PollenCollector.init(),
            .life = components.Lifespan.init(spawners.newBeeLifespan()),
        });
        self.simulated[@intFromEnum(beeType)] += 1;
        return index;
    }

    /// Set the colony size of a type directly (loading). Never below the
    /// number already simulated.
    pub fn setPopulation(self: *Store, beeType: BeeType, n: u32) void {
        const t = @intFromEnum(beeType);
        self.population[t] = @max(@min(n, MAX_PER_TYPE), self.simulated[t]);
        self.needsRebalance = true;
    }

    /// Drop a simulated bee, releasing its flower claim. Population is
    /// untouched: callers decide whether the colony shrank or the bee is
    /// merely going dormant.
    pub fn removeSimulated(self: *Store, world: *World, index: usize) void {
        const ai = self.list.items(.ai)[index];
        if (ai.targetLocked and !ai.carryingPollen) {
            if (ai.targetEntity) |target| {
                if (world.getFlowerGrowth(target) != null) world.decrementFlowerTarget(target);
            }
        }
        self.simulated[@intFromEnum(ai.beeType)] -= 1;
        self.list.swapRemove(index);
    }

    /// Bring the simulated mix back to `apportion(population, SIM_CAP)`:
    /// over-represented types lose idle representatives first (bees on a
    /// trip keep their pollen), under-represented ones gain fresh bees on
    /// the meadow.
    pub fn rebalance(self: *Store, world: *World) !void {
        self.needsRebalance = false;
        const target = apportion(self.population, SIM_CAP);

        // Shrink first so the list never exceeds the cap mid-way.
        for (0..TYPE_COUNT) |t| {
            if (self.simulated[t] <= target[t]) continue;
            var excess = self.simulated[t] - target[t];
            excess -= self.removeIdle(world, @enumFromInt(t), excess);
            if (excess > 0) excess -= self.removeAny(world, @enumFromInt(t), excess);
        }
        for (0..TYPE_COUNT) |t| {
            while (self.simulated[t] < target[t]) {
                _ = try self.spawnSimulated(@enumFromInt(t), self.meadow.randomPos());
            }
        }
    }

    fn removeIdle(self: *Store, world: *World, beeType: BeeType, max: u32) u32 {
        var removed: u32 = 0;
        var i = self.list.len;
        while (i > 0 and removed < max) {
            i -= 1;
            const ai = self.list.items(.ai)[i];
            if (ai.beeType != beeType or ai.targetLocked or ai.carryingPollen) continue;
            self.removeSimulated(world, i);
            removed += 1;
        }
        return removed;
    }

    fn removeAny(self: *Store, world: *World, beeType: BeeType, max: u32) u32 {
        var removed: u32 = 0;
        var i = self.list.len;
        while (i > 0 and removed < max) {
            i -= 1;
            if (self.list.items(.ai)[i].beeType != beeType) continue;
            self.removeSimulated(world, i);
            removed += 1;
        }
        return removed;
    }

    /// Age every simulated bee (only when bees are mortal). A bee that dies
    /// carrying pollen spends it on +50% lifespan instead; any other death
    /// shrinks the colony by one and, while dormant bees remain, is refilled
    /// by the next rebalance.
    pub fn age(self: *Store, world: *World, deltaTime: f32) void {
        for (&self.puffs) |*puff| puff.age += deltaTime;
        var i = self.list.len;
        while (i > 0) {
            i -= 1;
            const life = &self.list.items(.life)[i];
            life.timeAlive += deltaTime;
            life.totalTimeAlive += deltaTime;
            if (!life.isDead()) continue;

            const ai = &self.list.items(.ai)[i];
            if (ai.carryingPollen) {
                life.timeSpan += life.timeSpan * 0.5;
                life.timeAlive = 0;
                ai.carryingPollen = false;
                ai.tripLoads = 0;
                ai.targetLocked = false;
                ai.targetEntity = null;
                self.list.items(.collector)[i].pollenCollected = 0;
                continue;
            }
            const t = @intFromEnum(ai.beeType);
            const pos = self.list.items(.pos)[i];
            self.puffs[self.puffNext] = .{ .x = pos.x, .y = pos.y, .age = 0 };
            self.puffNext = (self.puffNext + 1) % MAX_PUFFS;
            self.removeSimulated(world, i);
            self.population[t] -= 1;
            self.needsRebalance = true;
        }
    }

    /// Puffs still fading (for tests / the renderer).
    pub fn activePuffs(self: *const Store) usize {
        var n: usize = 0;
        for (self.puffs) |puff| {
            if (puff.age < PUFF_LIFETIME) n += 1;
        }
        return n;
    }

    /// Bee positions are screen-space; carry them along with the meadow
    /// whenever it shifts (pan, resize, grid growth).
    pub fn translate(self: *Store, delta: rl.Vector2) void {
        for (self.list.items(.pos)) |*pos| {
            pos.x += delta.x;
            pos.y += delta.y;
        }
        for (&self.puffs) |*puff| {
            puff.x += delta.x;
            puff.y += delta.y;
        }
        self.meadow.offset.x += delta.x;
        self.meadow.offset.y += delta.y;
    }

    /// Stretch every living bee's lifespan (Bee Vitality purchase / load).
    pub fn multiplyLifespans(self: *Store, factor: f32) void {
        for (self.list.items(.life)) |*life| life.timeSpan *= factor;
    }

    /// Grid growth inserts a ring: locked targets shift with the tiles.
    pub fn shiftTargets(self: *Store, dx: f32, dy: f32) void {
        for (self.list.items(.ai)) |*ai| {
            if (ai.targetLocked) {
                ai.targetGridX += dx;
                ai.targetGridY += dy;
            }
        }
    }
};

fn testWorld() World {
    return World.init(std.testing.allocator);
}

test "apportion keeps small colonies whole and splits big ones proportionally" {
    try std.testing.expectEqual([4]u32{ 8, 0, 0, 0 }, apportion(.{ 8, 0, 0, 0 }, 50));
    try std.testing.expectEqual([4]u32{ 30, 10, 10, 0 }, apportion(.{ 30, 10, 10, 0 }, 50));

    const split = apportion(.{ 900_000, 60_000, 30_000, 10_000 }, 50_000);
    try std.testing.expectEqual([4]u32{ 45_000, 3_000, 1_500, 500 }, split);

    // Rounding never loses or invents a slot.
    const odd = apportion(.{ 7, 7, 7, 1 }, 10);
    var sum: u32 = 0;
    for (odd) |n| sum += n;
    try std.testing.expectEqual(@as(u32, 10), sum);
}

test "apportion always simulates at least one bee of every owned type" {
    const split = apportion(.{ 1_000_000, 0, 0, 1 }, 50_000);
    try std.testing.expectEqual(@as(u32, 49_999), split[0]);
    try std.testing.expectEqual(@as(u32, 1), split[3]);
    try std.testing.expectEqual(@as(u32, 0), split[1]);
}

test "bees past the cap go dormant and the mix re-proportions on rebalance" {
    var world = testWorld();
    defer world.deinit();
    const store = &world.bees;

    for (0..SIM_CAP) |_| try std.testing.expect(try store.add(.worker));
    try std.testing.expectEqual(SIM_CAP, store.list.len);
    try std.testing.expectEqual(@as(u64, 0), store.dormant());

    // Past the cap: counted, not simulated.
    for (0..SIM_CAP) |_| try std.testing.expect(try store.add(.gardener));
    try std.testing.expectEqual(@as(u64, 2 * SIM_CAP), store.total());
    try std.testing.expectEqual(SIM_CAP, store.list.len);
    try std.testing.expectEqual(@as(u64, SIM_CAP), store.dormant());
    try std.testing.expect(store.needsRebalance);

    try world.rebalanceBees();
    try std.testing.expect(!store.needsRebalance);
    try std.testing.expectEqual(SIM_CAP, store.list.len);
    try std.testing.expectEqual(@as(u32, SIM_CAP / 2), store.simulated[@intFromEnum(BeeType.worker)]);
    try std.testing.expectEqual(@as(u32, SIM_CAP / 2), store.simulated[@intFromEnum(BeeType.gardener)]);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), store.weight(.gardener), 1e-6);
    // Population untouched by the reshuffle.
    try std.testing.expectEqual(@as(u32, SIM_CAP), store.count(.worker));
    try std.testing.expectEqual(@as(u32, SIM_CAP), store.count(.gardener));

    // The simulated per-type tallies match the list.
    var tally: [TYPE_COUNT]u32 = @splat(0);
    for (store.list.items(.ai)) |ai| tally[@intFromEnum(ai.beeType)] += 1;
    try std.testing.expectEqual(tally, store.simulated);
}

test "rebalance releases the flower claims of the bees it retires" {
    var world = testWorld();
    defer world.deinit();
    const store = &world.bees;

    // A fake flower, claimed by every worker.
    const flower = try world.createEntity();
    try world.addFlowerGrowth(flower, components.FlowerGrowth.init(.rose));
    for (0..SIM_CAP) |_| _ = try store.add(.worker);
    for (store.list.items(.ai)) |*ai| {
        ai.targetLocked = true;
        ai.targetEntity = flower;
        world.incrementFlowerTarget(flower);
    }
    try std.testing.expectEqual(@as(u32, SIM_CAP), world.getFlowerTargetCount(flower));

    // Half the colony becomes swift: half the workers retire.
    for (0..SIM_CAP) |_| _ = try store.add(.swift);
    try world.rebalanceBees();
    try std.testing.expectEqual(@as(u32, SIM_CAP / 2), world.getFlowerTargetCount(flower));
}

test "setPopulation never drops below what is already simulated" {
    var world = testWorld();
    defer world.deinit();
    for (0..10) |_| _ = try world.bees.add(.worker);
    world.bees.setPopulation(.worker, 3);
    try std.testing.expectEqual(@as(u32, 10), world.bees.count(.worker));
    world.bees.setPopulation(.worker, 500);
    try std.testing.expectEqual(@as(u32, 500), world.bees.count(.worker));
    try std.testing.expectEqual(@as(u64, 490), world.bees.dormant());
}

test "aging refunds a pollen carrier and retires the rest" {
    var world = testWorld();
    defer world.deinit();
    const store = &world.bees;
    _ = try store.add(.worker);
    _ = try store.add(.worker);
    store.list.items(.life)[0].timeSpan = 1;
    store.list.items(.life)[1].timeSpan = 1;
    store.list.items(.ai)[1].carryingPollen = true;

    store.age(&world, 2);
    try std.testing.expectEqual(@as(usize, 1), store.list.len);
    try std.testing.expectEqual(@as(u32, 1), store.count(.worker));
    try std.testing.expect(!store.list.items(.ai)[0].carryingPollen);
    try std.testing.expectEqual(@as(f32, 1.5), store.list.items(.life)[0].timeSpan);
}

test "a death leaves a puff that fades out (#69)" {
    var world = testWorld();
    defer world.deinit();
    const store = &world.bees;
    _ = try store.add(.worker);
    try std.testing.expectEqual(@as(usize, 0), store.activePuffs());
    store.list.items(.life)[0].timeSpan = 1;
    store.age(&world, 2);
    try std.testing.expectEqual(@as(usize, 0), store.list.len);
    try std.testing.expectEqual(@as(usize, 1), store.activePuffs());
    store.age(&world, PUFF_LIFETIME);
    try std.testing.expectEqual(@as(usize, 0), store.activePuffs());
}
