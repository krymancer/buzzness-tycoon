const rl = @import("raylib");
const std = @import("std");

/// Resource management for the game economy.
/// Currently manages honey which can be spent to create new bees
/// or upgrade the beehive.
pub const Resources = struct {
    honey: f32,

    pub fn init() @This() {
        return .{
            .honey = 69420.0,
        };
    }

    pub fn deinit(self: @This()) void {
        _ = self;
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
