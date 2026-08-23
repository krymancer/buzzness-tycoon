const std = @import("std");

pub const NodeId = u16;

pub const EffectKind = enum {
    honey_factor_mul,
    storage_add,
    growth_cd_sub,
    bee_unlock_worker,
    bee_unlock_swift,
    bee_unlock_efficient,
    bee_unlock_gardener,
    grid_expand,
    lab_aura,
    aura_reach,
    prestige_unlock,
    growth_boost_unlock,
    super_flower_unlock,
};

/// Marks a node as re-buyable. Each purchase raises its level and re-applies
/// the node's effect; the cost scales geometrically: cost * cost_growth^level.
pub const Repeat = struct {
    cost_growth: f32,
    /// 0 = unlimited.
    max_level: u16 = 0,
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

    pub fn isMaxed(self: *const @This(), level: u16) bool {
        const r = self.repeat orelse return level > 0;
        return r.max_level != 0 and level >= r.max_level;
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
    .{ .id = 22, .name = "Honey x16", .cost = 6000, .prereqs = &[_]NodeId{3}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 4 },
    .{ .id = 23, .name = "Honey x32", .cost = 20000, .prereqs = &[_]NodeId{22}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 5 },
    // Repeatable: +25% honey per level, cost x1.6 per level, no cap.
    .{ .id = 24, .name = "Honey Boost", .cost = 15000, .prereqs = &[_]NodeId{23}, .effect = .honey_factor_mul, .value = 1.25, .col = -2, .row = 6, .repeat = .{ .cost_growth = 1.6 } },

    // Bees branch (col -1)
    .{ .id = 4, .name = "Swift Bee", .cost = 80, .prereqs = r_worker, .effect = .bee_unlock_swift, .col = -1, .row = 1 },
    .{ .id = 5, .name = "Efficient Bee", .cost = 400, .prereqs = &[_]NodeId{4}, .effect = .bee_unlock_efficient, .col = -1, .row = 2 },
    .{ .id = 6, .name = "Gardener Bee", .cost = 2000, .prereqs = &[_]NodeId{5}, .effect = .bee_unlock_gardener, .col = -1, .row = 3 },

    // Growth (col 0, below Instant Grow which gates it). Repeatable: each
    // level shaves `value` seconds off the Instant Grow cooldown (floor 2s).
    .{ .id = 7, .name = "Grow Speed", .cost = 60, .prereqs = &[_]NodeId{20}, .effect = .growth_cd_sub, .value = 1.0, .col = 0, .row = 2, .repeat = .{ .cost_growth = 1.7, .max_level = 8 } },
    // (ids 8/9 were Grow CD -3s/-6s — folded into 7's levels on load.)

    // Grid (col 1). Repeatable: +1 ring per level.
    .{ .id = 10, .name = "Grid Ring", .cost = 150, .prereqs = r_worker, .effect = .grid_expand, .value = 1, .col = 1, .row = 1, .repeat = .{ .cost_growth = 3.0, .max_level = 10 } },
    // (ids 11/12 were Grid +2/+3 ring — folded into 10's levels on load.)

    // Storage (col 2). Repeatable: adds value * 1.6^level capacity per level.
    .{ .id = 13, .name = "Storage", .cost = 40, .prereqs = r_worker, .effect = .storage_add, .value = 500, .col = 2, .row = 1, .repeat = .{ .cost_growth = 1.8 } },
    // (ids 14/15 were Storage +1K/+2K — folded into 13's levels on load.)

    // Labs branch (col 0, rows 4-6) — gated behind cross-branch t3 nodes
    // Aura: flowers inside the rings around the hive yield more pollen.
    // Lab: Aura levels the factor (+25%/level); Aura Reach widens the rings
    // (+1 tile/level). Both repeatable.
    .{ .id = 16, .name = "Lab: Aura", .cost = 8000, .prereqs = &[_]NodeId{ 3, 6 }, .effect = .lab_aura, .col = 0, .row = 4, .repeat = .{ .cost_growth = 1.8 } },
    .{ .id = 25, .name = "Aura Reach", .cost = 5000, .prereqs = &[_]NodeId{16}, .effect = .aura_reach, .col = 0, .row = 5, .repeat = .{ .cost_growth = 1.6 } },
    // (ids 17/18 were Lab: Burst / Lab: Bloom — removed; stale save entries are ignored.)
    .{ .id = 19, .name = "Prestige", .cost = 100000, .prereqs = &[_]NodeId{ 25, 21 }, .effect = .prestige_unlock, .col = 0, .row = 6 },

    // Instant Grow: unlocks the click-a-flower growth boost (was always-on).
    .{ .id = 20, .name = "Instant Grow", .cost = 30, .prereqs = r_worker, .effect = .growth_boost_unlock, .col = 0, .row = 1 },
    // Super Flowers: 2x2 same-type blocks merge into an 8x SUPER flower.
    .{ .id = 21, .name = "Super Flowers", .cost = 3500, .prereqs = &[_]NodeId{ 7, 10 }, .effect = .super_flower_unlock, .col = 1, .row = 4 },
};

pub const ROOT_ID: NodeId = 0;
pub const AURA_ID: NodeId = 16;
pub const AURA_REACH_ID: NodeId = 25;

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

    /// True when the node can be bought (first purchase) or leveled up again.
    pub fn canBuy(self: *const @This(), node: *const Node) bool {
        return self.isUnlocked(node) and !node.isMaxed(self.level(node.id));
    }

    /// Honey price of the next purchase of this node.
    pub fn nextCost(self: *const @This(), node: *const Node) f32 {
        return node.costAtLevel(self.level(node.id));
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
};

test "repeatable node cost grows geometrically and one-shot nodes max at level 1" {
    const boost = findNode(24).?;
    try std.testing.expectApproxEqRel(@as(f32, 15000), boost.costAtLevel(0), 1e-5);
    try std.testing.expectApproxEqRel(@as(f32, 15000 * 1.6), boost.costAtLevel(1), 1e-5);
    try std.testing.expect(!boost.isMaxed(50));

    const honey2 = findNode(1).?;
    try std.testing.expectEqual(@as(f32, 50), honey2.costAtLevel(0));
    try std.testing.expect(!honey2.isMaxed(0));
    try std.testing.expect(honey2.isMaxed(1));
}

test "state tracks levels and gates buying" {
    var s = State.init(std.testing.allocator);
    defer s.deinit();
    const honey2 = findNode(1).?;
    try std.testing.expect(s.canBuy(honey2));
    try s.markPurchased(1);
    try std.testing.expect(!s.canBuy(honey2));
    try std.testing.expectEqual(@as(u16, 1), s.level(1));

    const boost = findNode(24).?;
    try std.testing.expect(!s.canBuy(boost)); // prereqs missing
    try s.setLevel(23, 1);
    try std.testing.expect(s.canBuy(boost));
    try s.markPurchased(24);
    try s.markPurchased(24);
    try std.testing.expectEqual(@as(u16, 2), s.level(24));
    try std.testing.expect(s.canBuy(boost));
    try std.testing.expectApproxEqRel(@as(f32, 15000 * 1.6 * 1.6), s.nextCost(boost), 1e-5);
}
