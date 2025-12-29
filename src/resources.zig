const rl = @import("raylib");
const std = @import("std");

pub const Resources = struct {
    honey: f32,

    pub fn init() @This() {
        return .{ .honey = 69420.0 };
    }

    pub fn addHoney(self: *@This(), amount: f32) void {
        self.honey += amount;
    }

    pub fn spendHoney(self: *@This(), amount: f32) bool {
        if (self.honey >= amount) {
            self.honey -= amount;
            return true;
        }
        return false;
    }
};
