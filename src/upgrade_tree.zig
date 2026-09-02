const std = @import("std");
const lifespan_system = @import("ecs/systems/lifespan_system.zig");

pub const NodeId = u16;

pub const EffectKind = enum {
    honey_factor_mul,
    storage_add,
    growth_cd_sub,
    bee_unlock_worker,
    bee_unlock_swift,
    bee_unlock_efficient,
    bee_unlock_gardener,
    gardener_chance,
    /// Composting: gardeners clear rot they cross and hunt down the rest.
    gardener_compost,
    /// Seed Scouts: idle gardeners seek out empty tiles and plant them.
    gardener_sow,
    bulk_buy_tier,
    flower_growth_mul,
    bee_lifespan_mul,
    rot_chance_sub,
    grid_expand,
    lab_aura,
    aura_reach,
    prestige_unlock,
    growth_boost_unlock,
    super_flower_unlock,
    night_penalty_sub,
    /// Tailwind: every bee flies faster (x1.15 per level).
    bee_speed_mul,
    /// Saddlebags: bees visit one more flower per trip per level.
    bee_carry_add,
    /// Drills: one bee type flies and collects x1.1 better per level. The
    /// type comes from the node id (see TRAINING_IDS).
    bee_training,
};

/// Marks a node as re-buyable. Each purchase raises its level and re-applies
/// the node's effect; the cost scales geometrically: cost * cost_growth^level.
/// Every repeatable is capped per run: unlimited levels let one run stack
/// multipliers until the f32 economy overflowed to inf (#64), and a monster
/// first run bought out the Royal Shop on the second. Ascending raises the
/// cap, with no ceiling: inf stays reachable (Balatro-style), it just takes
/// a good many prestiges to get there.
pub const Repeat = struct {
    cost_growth: f32,
    /// Levels available on a fresh profile.
    max_level: u16,
    /// Extra cap levels granted per ascension (stats.prestigeCount). 0 for
    /// nodes whose cap is semantic (Night Shift's penalty is gone at 4).
    per_ascension: u16 = 0,

    /// Level cap for a profile with `ascensions` prestiges behind it.
    pub fn capAt(self: @This(), ascensions: u32) u16 {
        const grown = @as(u64, self.max_level) + @as(u64, self.per_ascension) * ascensions;
        return @intCast(@min(grown, std.math.maxInt(u16)));
    }
};

pub const Node = struct {
    id: NodeId,
    name: []const u8,
    cost: f32,
    prereqs: []const NodeId,
    effect: EffectKind,
    value: f32 = 0,
    col: i8,
    row: i8,
    repeat: ?Repeat = null,

    pub fn isRepeatable(self: *const @This()) bool {
        return self.repeat != null;
    }

    /// Cost to buy the node when it's currently at `level` (0 = not owned).
    pub fn costAtLevel(self: *const @This(), level: u16) f32 {
        const r = self.repeat orelse return self.cost;
        return self.cost * std.math.pow(f32, r.cost_growth, @floatFromInt(level));
    }

    pub fn isMaxed(self: *const @This(), level: u16, ascensions: u32) bool {
        const r = self.repeat orelse return level > 0;
        return level >= r.capAt(ascensions);
    }
};

const no_prereqs = &[_]NodeId{};
const r_worker = &[_]NodeId{0};

// Root node id 0 is Worker (auto-owned at game start).
// Tiers branch outward from root. Labs gate behind cross-branch t3 nodes.
pub const NODES = [_]Node{
    // id 0 — root (free, auto-owned). Unlocks the Worker bee only; Swift is
    // gated behind node 4 so it stays locked until purchased.
    .{ .id = 0, .name = "Worker Bee", .cost = 0, .prereqs = no_prereqs, .effect = .bee_unlock_worker, .value = 0, .col = 0, .row = 0 },

    // Honey branch (col -2)
    .{ .id = 1, .name = "Honey x2", .cost = 50, .prereqs = r_worker, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 1 },
    .{ .id = 2, .name = "Honey x4", .cost = 250, .prereqs = &[_]NodeId{1}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 2 },
    .{ .id = 3, .name = "Honey x8", .cost = 1500, .prereqs = &[_]NodeId{2}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 3 },
    .{ .id = 22, .name = "Honey x16", .cost = 3500, .prereqs = &[_]NodeId{3}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 4 },
    .{ .id = 23, .name = "Honey x32", .cost = 10000, .prereqs = &[_]NodeId{22}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 5 },
    // Repeatable: +25% honey per level, cost x1.5 per level; the per-run
    // cap grows with every ascension.
    .{ .id = 24, .name = "Honey Boost", .cost = 8000, .prereqs = &[_]NodeId{23}, .effect = .honey_factor_mul, .value = 1.25, .col = -2, .row = 6, .repeat = .{ .cost_growth = 1.5, .max_level = 10, .per_ascension = 5 } },

    // Bees branch (col -1)
    .{ .id = 4, .name = "Swift Bee", .cost = 80, .prereqs = r_worker, .effect = .bee_unlock_swift, .col = -1, .row = 1 },
    .{ .id = 5, .name = "Efficient Bee", .cost = 400, .prereqs = &[_]NodeId{4}, .effect = .bee_unlock_efficient, .col = -1, .row = 2 },
    .{ .id = 6, .name = "Gardener Bee", .cost = 2000, .prereqs = &[_]NodeId{5}, .effect = .bee_unlock_gardener, .col = -1, .row = 3 },
    // Repeatable: gardener plant chance 20% -> +10%/level (caps at 100%).
    .{ .id = 26, .name = "Green Thumb", .cost = 2500, .prereqs = &[_]NodeId{6}, .effect = .gardener_chance, .col = -1, .row = 4, .repeat = .{ .cost_growth = 1.5, .max_level = 8 } },
    // Gardeners clear rotten flowers they fly over (then may replant there).
    .{ .id = 27, .name = "Composting", .cost = 6000, .prereqs = &[_]NodeId{26}, .effect = .gardener_compost, .col = -1, .row = 5 },
    // Gardeners actively seek out rotten flowers and fly there to clear them.
    .{ .id = 28, .name = "Seed Scouts", .cost = 15000, .prereqs = &[_]NodeId{27}, .effect = .gardener_sow, .col = -1, .row = 6 },

    // Growth (col 0, below Instant Grow which gates it). Repeatable: each
    // level shaves `value` seconds off the Instant Grow cooldown (floor 2s).
    .{ .id = 7, .name = "Grow Speed", .cost = 60, .prereqs = &[_]NodeId{20}, .effect = .growth_cd_sub, .value = 1.0, .col = 0, .row = 2, .repeat = .{ .cost_growth = 1.7, .max_level = 8 } },
    // (ids 8/9 were Grow CD -3s/-6s — folded into 7's levels on load.)

    // Grid (col 1). Repeatable: +1 ring per level.
    .{ .id = 10, .name = "Grid Ring", .cost = 150, .prereqs = r_worker, .effect = .grid_expand, .value = 1, .col = 1, .row = 1, .repeat = .{ .cost_growth = 3.0, .max_level = 20 } },
    // (ids 11/12 were Grid +2/+3 ring — folded into 10's levels on load.)
    // Each level adds one step to the bee buy-quantity cycle: x50, x100,
    // x500, x1000 (see action_hud.BUY_QTYS).
    // Saddlebags: +1 flower per trip per level before the bee flies home.
    // Past a handful the round trip outgrows the gain, so the cap is short
    // and grows slowly with ascension (#68).
    .{ .id = 35, .name = "Saddlebags", .cost = 10000, .prereqs = r_worker, .effect = .bee_carry_add, .value = 1, .col = 1, .row = 3, .repeat = .{ .cost_growth = 2.0, .max_level = 4, .per_ascension = 1 } },
    .{ .id = 32, .name = "Bulk Order", .cost = 3000, .prereqs = &[_]NodeId{10}, .effect = .bulk_buy_tier, .col = 1, .row = 2, .repeat = .{ .cost_growth = 4.0, .max_level = 4 } },

    // Drills (col 3): per-type training, one repeatable per bee type. Bee
    // prices stay flat (#66), so this is what makes a type worth investing
    // in beyond "buy more". Each gates on its type's unlock node.
    .{ .id = 36, .name = "Worker Drills", .cost = 200, .prereqs = r_worker, .effect = .bee_training, .value = 1.1, .col = 3, .row = 1, .repeat = .{ .cost_growth = 1.6, .max_level = 5, .per_ascension = 2 } },
    .{ .id = 37, .name = "Swift Drills", .cost = 600, .prereqs = &[_]NodeId{4}, .effect = .bee_training, .value = 1.1, .col = 3, .row = 2, .repeat = .{ .cost_growth = 1.6, .max_level = 5, .per_ascension = 2 } },
    .{ .id = 38, .name = "Efficient Drills", .cost = 1500, .prereqs = &[_]NodeId{5}, .effect = .bee_training, .value = 1.1, .col = 3, .row = 3, .repeat = .{ .cost_growth = 1.6, .max_level = 5, .per_ascension = 2 } },
    .{ .id = 39, .name = "Gardener Drills", .cost = 4000, .prereqs = &[_]NodeId{6}, .effect = .bee_training, .value = 1.1, .col = 3, .row = 4, .repeat = .{ .cost_growth = 1.6, .max_level = 5, .per_ascension = 2 } },

    // Storage (col 2). Repeatable: adds value * STORAGE_CAPACITY_GROWTH^level
    // capacity per level. cost_growth must never exceed the capacity growth:
    // honey is capped at the current capacity, so a faster-growing cost
    // eventually becomes unreachable and softlocks progression. This cap
    // paces the whole economy: honey can never exceed the capacity this
    // node builds, so its per-ascension growth is what decides how many
    // prestiges it takes before a run can reach f32 infinity (~11).
    .{ .id = 13, .name = "Storage", .cost = 40, .prereqs = r_worker, .effect = .storage_add, .value = 500, .col = 2, .row = 1, .repeat = .{ .cost_growth = STORAGE_CAPACITY_GROWTH, .max_level = 30, .per_ascension = 10 } },
    // (ids 14/15 were Storage +1K/+2K — folded into 13's levels on load.)

    // Colony vitality (col 2, under Storage). Available from the start;
    // flowers mature/re-pollen faster (x1.2/level), bees live longer
    // (x1.2/level), dying flowers rot less (-10%/level, gone at 6: a
    // semantic cap like Night Shift, so ascending adds nothing).
    .{ .id = 29, .name = "Fertile Soil", .cost = 300, .prereqs = r_worker, .effect = .flower_growth_mul, .value = 1.2, .col = 2, .row = 2, .repeat = .{ .cost_growth = 1.6, .max_level = 15, .per_ascension = 5 } },
    // Bee Vitality: x1.2 lifespan per level; 10 levels is x6.2, a bee that
    // lives most of an hour, so the cap is a real ceiling the player feels.
    .{ .id = 30, .name = "Bee Vitality", .cost = 800, .prereqs = r_worker, .effect = .bee_lifespan_mul, .value = 1.2, .col = 2, .row = 3, .repeat = .{ .cost_growth = 1.7, .max_level = 10, .per_ascension = 2 } },
    .{ .id = 31, .name = "Hardy Blooms", .cost = 2500, .prereqs = r_worker, .effect = .rot_chance_sub, .value = 10, .col = 2, .row = 4, .repeat = .{ .cost_growth = 1.8, .max_level = lifespan_system.HARDY_BLOOMS_MAX_LEVEL } },
    // Bees produce half honey and fly slower at night (see bee_ai_system);
    // each level removes a quarter of the penalty, all of it at level 4.
    .{ .id = 33, .name = "Night Shift", .cost = 2000, .prereqs = r_worker, .effect = .night_penalty_sub, .col = 2, .row = 5, .repeat = .{ .cost_growth = 1.8, .max_level = 4 } },
    // Tailwind: all bees fly x1.15 faster per level (multiplies Swift's x2
    // and the night debuff). A direct throughput lever, so the cap grows
    // with ascension like the honey line (#67).
    .{ .id = 34, .name = "Tailwind", .cost = 1500, .prereqs = r_worker, .effect = .bee_speed_mul, .value = 1.15, .col = 2, .row = 6, .repeat = .{ .cost_growth = 1.7, .max_level = 5, .per_ascension = 2 } },

    // Labs branch (col 0, rows 4-6) — gated behind cross-branch t3 nodes
    // Aura: flowers inside the rings around the hive yield more pollen.
    // Lab: Aura levels the factor (+25%/level); Aura Reach widens the rings
    // (+1 tile/level). Both repeatable.
    .{ .id = 16, .name = "Lab: Aura", .cost = 8000, .prereqs = &[_]NodeId{ 3, 6 }, .effect = .lab_aura, .col = 0, .row = 4, .repeat = .{ .cost_growth = 1.8, .max_level = 15, .per_ascension = 5 } },
    // Semantic cap: reach past the biggest possible meadow (20 tree rings +
    // 12 shop rings) would be dead levels, so it stops there for good.
    .{ .id = 25, .name = "Aura Reach", .cost = 5000, .prereqs = &[_]NodeId{16}, .effect = .aura_reach, .col = 0, .row = 5, .repeat = .{ .cost_growth = 1.6, .max_level = 32 } },
    // (ids 17/18 were Lab: Burst / Lab: Bloom — removed; stale save entries are ignored.)
    .{ .id = 19, .name = "Prestige", .cost = 100000, .prereqs = &[_]NodeId{ 25, 21 }, .effect = .prestige_unlock, .col = 0, .row = 6 },

    // Instant Grow: unlocks the click-a-flower growth boost (was always-on).
    .{ .id = 20, .name = "Instant Grow", .cost = 30, .prereqs = r_worker, .effect = .growth_boost_unlock, .col = 0, .row = 1 },
    // Super Flowers: 2x2 same-type blocks merge into an 8x SUPER flower.
    .{ .id = 21, .name = "Super Flowers", .cost = 3500, .prereqs = &[_]NodeId{ 7, 10 }, .effect = .super_flower_unlock, .col = 1, .row = 4 },
};

pub const ROOT_ID: NodeId = 0;
pub const STORAGE_ID: NodeId = 13;
pub const AURA_ID: NodeId = 16;
pub const PRESTIGE_ID: NodeId = 19;

/// Per-level growth of the capacity granted by the Storage node (game.zig
/// applies value * this^level on purchase). The node's cost_growth is tied to
/// this value so the next upgrade always fits inside the honey cap.
pub const STORAGE_CAPACITY_GROWTH: f32 = 1.6;
pub const AURA_REACH_ID: NodeId = 25;
pub const GREEN_THUMB_ID: NodeId = 26;
pub const FERTILE_SOIL_ID: NodeId = 29;
pub const BEE_VITALITY_ID: NodeId = 30;
pub const HARDY_BLOOMS_ID: NodeId = 31;
pub const TAILWIND_ID: NodeId = 34;
pub const SADDLEBAGS_ID: NodeId = 35;
/// Drills nodes indexed by @intFromEnum(BeeType): worker, swift, efficient, gardener.
pub const TRAINING_IDS = [_]NodeId{ 36, 37, 38, 39 };

/// Which bee type a Drills node trains (its index into TRAINING_IDS).
pub fn trainingType(id: NodeId) ?usize {
    for (TRAINING_IDS, 0..) |tid, t| {
        if (tid == id) return t;
    }
    return null;
}
pub const BULK_ORDER_ID: NodeId = 32;
pub const NIGHT_SHIFT_ID: NodeId = 33;

/// Old one-shot chains that are now single repeatable nodes. Each legacy id
/// purchased in an old save counts as +1 level on its target.
pub const LEGACY_LEVEL_MAP = [_]struct { legacy: NodeId, target: NodeId }{
    .{ .legacy = 8, .target = 7 },
    .{ .legacy = 9, .target = 7 },
    .{ .legacy = 11, .target = 10 },
    .{ .legacy = 12, .target = 10 },
    .{ .legacy = 14, .target = 13 },
    .{ .legacy = 15, .target = 13 },
};

pub fn findNode(id: NodeId) ?*const Node {
    for (&NODES) |*n| {
        if (n.id == id) return n;
    }
    return null;
}

pub const State = struct {
    /// node id -> level (absent or 0 = not owned; one-shot nodes are 0 or 1).
    levels: std.AutoHashMap(NodeId, u16),

    pub fn init(allocator: std.mem.Allocator) @This() {
        var s: @This() = .{ .levels = std.AutoHashMap(NodeId, u16).init(allocator) };
        s.levels.put(ROOT_ID, 1) catch {};
        return s;
    }

    pub fn deinit(self: *@This()) void {
        self.levels.deinit();
    }

    pub fn level(self: *const @This(), id: NodeId) u16 {
        return self.levels.get(id) orelse 0;
    }

    pub fn isPurchased(self: *const @This(), id: NodeId) bool {
        return self.level(id) > 0;
    }

    pub fn isUnlocked(self: *const @This(), node: *const Node) bool {
        for (node.prereqs) |pid| {
            if (!self.isPurchased(pid)) return false;
        }
        return true;
    }

    /// True when the node can be bought (first purchase) or leveled up
    /// again. `ascensions` (stats.prestigeCount) raises repeatable caps.
    pub fn canBuy(self: *const @This(), node: *const Node, ascensions: u32) bool {
        return self.isUnlocked(node) and !node.isMaxed(self.level(node.id), ascensions);
    }

    /// Honey price of the next purchase of this node. `prestigeCostMul` is
    /// the global prestige price multiplier (PrestigeState.costMul), so each
    /// prestige run keeps a real cost curve. Storage is exempt: its price
    /// must stay inside the honey capacity, which does not prestige-scale,
    /// or the next capacity upgrade becomes unaffordable and softlocks.
    pub fn nextCost(self: *const @This(), node: *const Node, prestigeCostMul: f32) f32 {
        const base = node.costAtLevel(self.level(node.id));
        return if (node.effect == .storage_add) base else base * prestigeCostMul;
    }

    /// Raise the node by one level (first purchase = level 1).
    pub fn markPurchased(self: *@This(), id: NodeId) !void {
        try self.levels.put(id, self.level(id) + 1);
    }

    pub fn setLevel(self: *@This(), id: NodeId, lvl: u16) !void {
        if (lvl == 0) {
            _ = self.levels.remove(id);
        } else {
            try self.levels.put(id, lvl);
        }
    }

    pub fn hasEffect(self: *const @This(), kind: EffectKind) bool {
        for (&NODES) |*n| {
            if (n.effect == kind and self.isPurchased(n.id)) return true;
        }
        return false;
    }

    pub fn beeUnlocked(self: *const @This(), kind: EffectKind) bool {
        return self.hasEffect(kind);
    }

    /// True once every non-repeatable node is owned ("Well Read").
    pub fn allOneShotsOwned(self: *const @This()) bool {
        for (&NODES) |*n| {
            if (n.repeat == null and !self.isPurchased(n.id)) return false;
        }
        return true;
    }
};

test "all one-shot nodes owned ignores repeatable levels" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    try std.testing.expect(!s.allOneShotsOwned());
    for (&NODES) |*n| {
        if (n.repeat == null) try s.setLevel(n.id, 1);
    }
    try std.testing.expect(s.allOneShotsOwned());
    // Repeatables never factor in.
    try s.setLevel(STORAGE_ID, 0);
    try std.testing.expect(s.allOneShotsOwned());
    try s.setLevel(21, 0);
    try std.testing.expect(!s.allOneShotsOwned());
}

test "repeatable node cost grows geometrically and one-shot nodes max at level 1" {
    const boost = findNode(24).?;
    try std.testing.expectApproxEqRel(@as(f32, 8000), boost.costAtLevel(0), 1e-5);
    try std.testing.expectApproxEqRel(@as(f32, 8000 * 1.5), boost.costAtLevel(1), 1e-5);
    try std.testing.expect(!boost.isMaxed(9, 0));
    try std.testing.expect(boost.isMaxed(10, 0));

    const honey2 = findNode(1).?;
    try std.testing.expectEqual(@as(f32, 50), honey2.costAtLevel(0));
    try std.testing.expect(!honey2.isMaxed(0, 0));
    try std.testing.expect(honey2.isMaxed(1, 0));
}

test "every repeatable is capped per run and ascending keeps raising the cap (#64)" {
    for (&NODES) |*n| {
        const r = n.repeat orelse continue;
        // No node may offer unlimited levels in one run again.
        try std.testing.expect(r.max_level != 0);
        try std.testing.expectEqual(r.max_level, r.capAt(0));
        try std.testing.expectEqual(r.max_level + r.per_ascension, r.capAt(1));
        // No hard ceiling: every prestige adds the same step, forever.
        try std.testing.expectEqual(r.max_level + 10 * r.per_ascension, r.capAt(10));
    }

    const boost = findNode(24).?;
    // An absurd ascension count saturates the u16 level instead of wrapping.
    try std.testing.expectEqual(@as(u16, std.math.maxInt(u16)), boost.repeat.?.capAt(1_000_000));
    // A grandfathered level above today's cap still reads as maxed.
    try std.testing.expect(boost.isMaxed(193, 0));
    try std.testing.expect(!boost.isMaxed(193, 40)); // 10 + 5*40 = 210
}

/// Honey capacity with Storage at `level` (Resources BASE_CAPACITY plus
/// every level's grant, the way game.zig applies them).
fn storageCapacityAt(level: u16) f32 {
    var capacity: f32 = 500;
    for (0..level) |l| capacity += 500 * std.math.pow(f32, STORAGE_CAPACITY_GROWTH, @floatFromInt(l));
    return capacity;
}

test "a fresh profile stays finite; reaching inf takes many ascensions (#64)" {
    // Honey never exceeds the capacity Storage builds, so Storage's cap is
    // what decides when a run can hit f32 infinity. Fresh profiles get a
    // late-game sized tank that is nowhere near it; inf is meant to be
    // reachable (Balatro-style) but only after a long stretch of prestiges.
    const storage = findNode(STORAGE_ID).?;
    const r = storage.repeat.?;
    const fresh = storageCapacityAt(r.capAt(0));
    try std.testing.expect(std.math.isFinite(fresh));
    try std.testing.expect(fresh > 1e8); // ~1.1e9 at Storage 30: the first run is meant to feel the cap
    try std.testing.expect(fresh < std.math.floatMax(f32) / 1e10);

    var ascensions: u32 = 0;
    while (std.math.isFinite(storageCapacityAt(r.capAt(ascensions)))) : (ascensions += 1) {}
    try std.testing.expect(ascensions >= 10);

    // The hive factor with the x2..x32 chain and Honey Boost at its fresh
    // cap, and every repeatable's last fresh-profile price, stay finite.
    const boost = findNode(24).?;
    const factor = 32.0 * std.math.pow(f32, boost.value, @floatFromInt(boost.repeat.?.max_level));
    try std.testing.expect(std.math.isFinite(factor));
    for (&NODES) |*n| {
        const rep = n.repeat orelse continue;
        try std.testing.expect(std.math.isFinite(n.costAtLevel(rep.max_level - 1)));
    }
}

test "storage upgrades never cost more than the capacity they build" {
    const storage = findNode(STORAGE_ID).?;
    var capacity: f32 = 500; // Resources BASE_CAPACITY
    // Up to the cap ten ascensions grant, the last stretch before f32 gives out.
    for (0..storage.repeat.?.capAt(10)) |level| {
        try std.testing.expect(storage.costAtLevel(@intCast(level)) <= capacity);
        capacity += storage.value * std.math.pow(f32, STORAGE_CAPACITY_GROWTH, @floatFromInt(level));
    }
    try std.testing.expectApproxEqRel(storageCapacityAt(storage.repeat.?.capAt(10)), capacity, 1e-4);
}

test "colony vitality nodes are buyable at start and cap by ascension" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    for ([_]NodeId{ FERTILE_SOIL_ID, BEE_VITALITY_ID }) |id| {
        const n = findNode(id).?;
        try std.testing.expect(s.canBuy(n, 0));
        const cap = n.repeat.?.max_level;
        try std.testing.expect(n.isMaxed(cap, 0));
        try std.testing.expect(!n.isMaxed(cap, 1)); // one ascend reopens it
    }
}

test "hardy blooms is buyable at start and its last level is where rot hits 0% (#70)" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const hardy = findNode(HARDY_BLOOMS_ID).?;
    try std.testing.expect(s.canBuy(hardy, 0));
    const cap = hardy.repeat.?.max_level;
    // Every level up to the cap still changes the number; the cap is 0%.
    var prev = lifespan_system.rotChanceForLevel(0);
    for (1..cap + 1) |lvl| {
        const cur = lifespan_system.rotChanceForLevel(@intCast(lvl));
        try std.testing.expect(cur < prev);
        prev = cur;
    }
    try std.testing.expectEqual(@as(i32, 0), lifespan_system.rotChanceForLevel(cap));
    // Semantic cap: ascending adds nothing.
    try std.testing.expect(hardy.isMaxed(cap, 0));
    try std.testing.expect(hardy.isMaxed(cap, 50));
}

test "tailwind is buyable at start and its cap grows with ascension (#67)" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const wind = findNode(TAILWIND_ID).?;
    try std.testing.expect(s.canBuy(wind, 0));
    try std.testing.expectApproxEqRel(@as(f32, 1500 * 1.7), wind.costAtLevel(1), 1e-5);
    const cap = wind.repeat.?.max_level;
    try std.testing.expect(wind.isMaxed(cap, 0));
    try std.testing.expect(!wind.isMaxed(cap, 1));
}

test "saddlebags is buyable at start with a short ascension-grown cap (#68)" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const bags = findNode(SADDLEBAGS_ID).?;
    try std.testing.expect(s.canBuy(bags, 0));
    try std.testing.expect(bags.isMaxed(4, 0));
    try std.testing.expect(!bags.isMaxed(4, 1));
}

test "drills: one capped repeatable per bee type, gated on the type's unlock (#66)" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    for (TRAINING_IDS, 0..) |id, t| {
        const n = findNode(id).?;
        try std.testing.expectEqual(EffectKind.bee_training, n.effect);
        try std.testing.expectEqual(t, trainingType(id).?);
        try std.testing.expect(n.isMaxed(n.repeat.?.max_level, 0));
        try std.testing.expect(!n.isMaxed(n.repeat.?.max_level, 1));
    }
    try std.testing.expect(s.canBuy(findNode(36).?, 0)); // workers are always owned
    try std.testing.expect(!s.canBuy(findNode(37).?, 0)); // Swift Bee not unlocked yet
    try s.setLevel(4, 1);
    try std.testing.expect(s.canBuy(findNode(37).?, 0));
    try std.testing.expectEqual(@as(?usize, null), trainingType(24));
}

test "night shift is buyable from the start and maxes at level 4" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const night = findNode(NIGHT_SHIFT_ID).?;
    try std.testing.expect(s.canBuy(night, 0));
    try std.testing.expectApproxEqRel(@as(f32, 2000 * 1.8), night.costAtLevel(1), 1e-5);
    try std.testing.expect(!night.isMaxed(3, 0));
    try std.testing.expect(night.isMaxed(4, 0));
    // Semantic cap (the penalty is fully gone at 4): ascending adds nothing.
    try std.testing.expect(night.isMaxed(4, 50));
}

test "bulk order has one level per unlockable buy step" {
    const action_hud = @import("ui/action_hud.zig");
    const bulk = findNode(BULK_ORDER_ID).?;
    // Three steps (x1/x10/x25) are always available; the tree adds one per
    // level up to x1000, the Royal Shop's Wholesale Contract the rest.
    try std.testing.expectEqual(action_hud.TREE_QTY_COUNT - action_hud.BASE_QTY_COUNT, @as(usize, bulk.repeat.?.max_level));
    const prestige = @import("prestige.zig");
    try std.testing.expectEqual(action_hud.BUY_QTYS.len - action_hud.TREE_QTY_COUNT, @as(usize, prestige.WHOLESALE_MAX_LEVEL));
}

test "state tracks levels and gates buying" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const honey2 = findNode(1).?;
    try std.testing.expect(s.canBuy(honey2, 0));
    try s.markPurchased(1);
    try std.testing.expect(!s.canBuy(honey2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.level(1));

    const boost = findNode(24).?;
    try std.testing.expect(!s.canBuy(boost, 0)); // prereqs missing
    try s.setLevel(23, 1);
    try std.testing.expect(s.canBuy(boost, 0));
    try s.markPurchased(24);
    try s.markPurchased(24);
    try std.testing.expectEqual(@as(u16, 2), s.level(24));
    try std.testing.expect(s.canBuy(boost, 0));
    try std.testing.expectApproxEqRel(@as(f32, 8000 * 1.5 * 1.5), s.nextCost(boost, 1.0), 1e-5);
}

test "prestige multiplier scales node prices but never storage" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();

    const honey2 = findNode(1).?;
    try std.testing.expectApproxEqRel(@as(f32, 50 * 1.3), s.nextCost(honey2, 1.3), 1e-5);

    const storage = findNode(STORAGE_ID).?;
    try std.testing.expectEqual(storage.cost, s.nextCost(storage, 1.3));
}
