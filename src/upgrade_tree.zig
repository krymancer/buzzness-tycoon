const std = @import("std");

pub const NodeId = u16;

pub const EffectKind = enum {
    honey_factor_mul,
    storage_add,
    growth_cd_sub,
    bee_unlock_swift,
    bee_unlock_efficient,
    bee_unlock_gardener,
    grid_expand,
    lab_aura,
    lab_burst,
    lab_bloom,
    prestige_unlock,
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
};

const no_prereqs = &[_]NodeId{};
const r_worker = &[_]NodeId{0};

// Root node id 0 is Worker (auto-owned at game start).
// Tiers branch outward from root. Labs gate behind cross-branch t3 nodes.
pub const NODES = [_]Node{
    // id 0 — root (free, auto-owned)
    .{ .id = 0, .name = "Worker Bee", .cost = 0, .prereqs = no_prereqs, .effect = .bee_unlock_swift, .value = 0, .col = 0, .row = 0 },

    // Honey branch (col -2)
    .{ .id = 1, .name = "Honey x2", .cost = 50, .prereqs = r_worker, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 1 },
    .{ .id = 2, .name = "Honey x4", .cost = 250, .prereqs = &[_]NodeId{1}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 2 },
    .{ .id = 3, .name = "Honey x8", .cost = 1500, .prereqs = &[_]NodeId{2}, .effect = .honey_factor_mul, .value = 2.0, .col = -2, .row = 3 },

    // Bees branch (col -1)
    .{ .id = 4, .name = "Swift Bee", .cost = 80, .prereqs = r_worker, .effect = .bee_unlock_swift, .col = -1, .row = 1 },
    .{ .id = 5, .name = "Efficient Bee", .cost = 400, .prereqs = &[_]NodeId{4}, .effect = .bee_unlock_efficient, .col = -1, .row = 2 },
    .{ .id = 6, .name = "Gardener Bee", .cost = 2000, .prereqs = &[_]NodeId{5}, .effect = .bee_unlock_gardener, .col = -1, .row = 3 },

    // Growth branch (col 0, directly below root)
    .{ .id = 7, .name = "Grow CD -1.5s", .cost = 60, .prereqs = r_worker, .effect = .growth_cd_sub, .value = 1.5, .col = 0, .row = 1 },
    .{ .id = 8, .name = "Grow CD -3s", .cost = 300, .prereqs = &[_]NodeId{7}, .effect = .growth_cd_sub, .value = 1.5, .col = 0, .row = 2 },
    .{ .id = 9, .name = "Grow CD -6s", .cost = 1800, .prereqs = &[_]NodeId{8}, .effect = .growth_cd_sub, .value = 3.0, .col = 0, .row = 3 },

    // Grid branch (col 1)
    .{ .id = 10, .name = "Grid +1 ring", .cost = 150, .prereqs = r_worker, .effect = .grid_expand, .value = 1, .col = 1, .row = 1 },
    .{ .id = 11, .name = "Grid +2 ring", .cost = 800, .prereqs = &[_]NodeId{10}, .effect = .grid_expand, .value = 1, .col = 1, .row = 2 },
    .{ .id = 12, .name = "Grid +3 ring", .cost = 5000, .prereqs = &[_]NodeId{11}, .effect = .grid_expand, .value = 1, .col = 1, .row = 3 },

    // Storage branch (col 2)
    .{ .id = 13, .name = "Storage +500", .cost = 40, .prereqs = r_worker, .effect = .storage_add, .value = 500, .col = 2, .row = 1 },
    .{ .id = 14, .name = "Storage +1K", .cost = 200, .prereqs = &[_]NodeId{13}, .effect = .storage_add, .value = 1000, .col = 2, .row = 2 },
    .{ .id = 15, .name = "Storage +2K", .cost = 1000, .prereqs = &[_]NodeId{14}, .effect = .storage_add, .value = 2000, .col = 2, .row = 3 },

    // Labs branch (col 0, rows 4-6) — gated behind cross-branch t3 nodes
    .{ .id = 16, .name = "Lab: Aura", .cost = 8000, .prereqs = &[_]NodeId{ 3, 6 }, .effect = .lab_aura, .col = 0, .row = 4 },
    .{ .id = 17, .name = "Lab: Burst", .cost = 25000, .prereqs = &[_]NodeId{ 16, 9 }, .effect = .lab_burst, .col = -1, .row = 5 },
    .{ .id = 18, .name = "Lab: Bloom", .cost = 25000, .prereqs = &[_]NodeId{ 16, 12 }, .effect = .lab_bloom, .col = 1, .row = 5 },
    .{ .id = 19, .name = "Prestige", .cost = 100000, .prereqs = &[_]NodeId{ 17, 18 }, .effect = .prestige_unlock, .col = 0, .row = 6 },
};

pub const ROOT_ID: NodeId = 0;

pub fn findNode(id: NodeId) ?*const Node {
    for (&NODES) |*n| {
        if (n.id == id) return n;
    }
    return null;
}

pub const State = struct {
    purchased: std.AutoHashMap(NodeId, void),

    pub fn init(allocator: std.mem.Allocator) @This() {
        var s: @This() = .{ .purchased = std.AutoHashMap(NodeId, void).init(allocator) };
        s.purchased.put(ROOT_ID, {}) catch {};
        return s;
    }

    pub fn deinit(self: *@This()) void {
        self.purchased.deinit();
    }

    pub fn isPurchased(self: *const @This(), id: NodeId) bool {
        return self.purchased.contains(id);
    }

    pub fn isUnlocked(self: *const @This(), node: *const Node) bool {
        for (node.prereqs) |pid| {
            if (!self.isPurchased(pid)) return false;
        }
        return true;
    }

    pub fn markPurchased(self: *@This(), id: NodeId) !void {
        try self.purchased.put(id, {});
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
