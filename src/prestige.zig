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

    pub fn resetRun(self: *@This(), gain: u32) void {
        self.royalJelly += gain;
        self.thisRunHoney = 0;
    }
};
