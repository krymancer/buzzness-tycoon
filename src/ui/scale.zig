//! Resolution-aware, player-adjustable UI sizing.
//!
//! Level 2 (200%) is deliberately the default for accessibility. Resolution
//! scaling then keeps that physical size consistent from 720p through 4K.

pub const MIN_LEVEL: u8 = 0;
pub const MAX_LEVEL: u8 = 2;
pub const DEFAULT_LEVEL: u8 = 2;

const multipliers = [_]f32{ 1.0, 1.5, 2.0 };
const percentages = [_]u16{ 100, 150, 200 };

var current_level: u8 = DEFAULT_LEVEL;

pub fn level() u8 {
    return current_level;
}

pub fn setLevel(value: u8) void {
    current_level = @min(value, MAX_LEVEL);
}

pub fn increase() void {
    if (current_level < MAX_LEVEL) current_level += 1;
}

pub fn decrease() void {
    if (current_level > MIN_LEVEL) current_level -= 1;
}

pub fn percentage() u16 {
    return percentages[current_level];
}

pub fn multiplier() f32 {
    return multipliers[current_level];
}

pub fn resolutionForHeight(screen_height: f32) f32 {
    return @min(2.0, @max(2.0 / 3.0, screen_height / 1080.0));
}

pub fn forHeight(screen_height: f32) f32 {
    return resolutionForHeight(screen_height) * multiplier();
}

pub fn font(base_size: i32, scale: f32) i32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(base_size)) * scale));
}

test "UI scale defaults to 200 percent and stays within its range" {
    const testing = @import("std").testing;

    setLevel(DEFAULT_LEVEL);
    try testing.expectEqual(@as(u16, 200), percentage());
    try testing.expectApproxEqAbs(@as(f32, 2.0), forHeight(1080), 0.001);

    increase();
    try testing.expectEqual(MAX_LEVEL, level());
    decrease();
    try testing.expectEqual(@as(u16, 150), percentage());

    setLevel(99);
    try testing.expectEqual(MAX_LEVEL, level());
    setLevel(DEFAULT_LEVEL);
}
