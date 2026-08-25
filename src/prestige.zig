const std = @import("std");

const HONEY_PER_JELLY: f32 = 10_000.0;
const MUL_PER_JELLY: f32 = 0.1;

pub const PrestigeState = struct {
    royalJelly: u32 = 0,
    thisRunHoney: f32 = 0,
    hasUnlockedPrestige: bool = false,

    pub fn trackHoney(self: *@This(), amount: f32) void {
        self.thisRunHoney += amount;
    }

    pub fn gainFromReset(self: *const @This()) u32 {
        if (self.thisRunHoney < HONEY_PER_JELLY) return 0;
        return @intFromFloat(@sqrt(self.thisRunHoney / HONEY_PER_JELLY));
    }

    pub fn globalMul(self: *const @This()) f32 {
        return 1.0 + MUL_PER_JELLY * @as(f32, @floatFromInt(self.royalJelly));
    }

    /// Global price multiplier for upgrade-tree nodes and bee purchases.
    /// Square root of the income multiplier: each prestige still nets faster
    /// progression overall (net speedup = sqrt(globalMul)), but prices rise
    /// enough that a run keeps a real pacing curve instead of blowing through
    /// the early tree.
    pub fn costMul(self: *const @This()) f32 {
        return @sqrt(self.globalMul());
    }

    pub fn resetRun(self: *@This(), gain: u32) void {
        self.royalJelly += gain;
        self.thisRunHoney = 0;
    }
};

test "cost multiplier grows slower than the income multiplier" {
    var p: PrestigeState = .{};
    try std.testing.expectEqual(@as(f32, 1.0), p.costMul());

    p.royalJelly = 10; // income x2.0
    try std.testing.expectApproxEqRel(@sqrt(@as(f32, 2.0)), p.costMul(), 1e-5);
    try std.testing.expect(p.costMul() < p.globalMul());
}
