//! The planting plan: the flower type the player has laid out on each cell
//! of the meadow (a blueprint). Empty planned cells draw as ghost flowers,
//! wild growth sprouts the planned type there, and gardeners head for
//! planned gaps first, so a layout persists as its flowers live and die.
//! Painting a plan is free; paying honey plants the flower on the spot.

const std = @import("std");
const components = @import("ecs/components.zig");
const grid_mod = @import("grid.zig");

pub const MAX: usize = grid_mod.MAX_WIDTH;
pub const CELLS: usize = MAX * MAX;
const NONE: u8 = 255;

var cells: [CELLS]u8 = @splat(NONE);
var planned: usize = 0;
/// Meadow size the plan is laid over (set by the game on init / load / expand).
pub var width: usize = 0;
pub var height: usize = 0;

pub fn reset() void {
    @memset(&cells, NONE);
    planned = 0;
}

pub fn count() usize {
    return planned;
}

fn index(x: i32, y: i32) ?usize {
    if (x < 0 or y < 0 or x >= @as(i32, @intCast(MAX)) or y >= @as(i32, @intCast(MAX))) return null;
    return @as(usize, @intCast(y)) * MAX + @as(usize, @intCast(x));
}

pub fn get(x: i32, y: i32) ?components.FlowerType {
    const i = index(x, y) orelse return null;
    return at(i);
}

pub fn at(i: usize) ?components.FlowerType {
    if (cells[i] == NONE) return null;
    return @enumFromInt(cells[i]);
}

/// Plan `t` on a cell, or clear it with null. Out-of-range cells are ignored.
pub fn set(x: i32, y: i32, t: ?components.FlowerType) void {
    const i = index(x, y) orelse return;
    const was = cells[i] != NONE;
    cells[i] = if (t) |ft| @intFromEnum(ft) else NONE;
    if (was and t == null) planned -= 1;
    if (!was and t != null) planned += 1;
}

/// Grid expansion adds a ring on every side, moving every cell by (+1, +1).
pub fn shift(dx: i32, dy: i32) void {
    var moved: [CELLS]u8 = @splat(NONE);
    var n: usize = 0;
    for (0..MAX) |y| {
        for (0..MAX) |x| {
            const v = cells[y * MAX + x];
            if (v == NONE) continue;
            const nx = @as(i32, @intCast(x)) + dx;
            const ny = @as(i32, @intCast(y)) + dy;
            const ni = index(nx, ny) orelse continue;
            moved[ni] = v;
            n += 1;
        }
    }
    cells = moved;
    planned = n;
}

test "set / get / count / shift" {
    reset();
    try std.testing.expectEqual(@as(usize, 0), count());
    set(3, 4, .tulip);
    set(3, 4, .tulip);
    set(0, 0, .rose);
    try std.testing.expectEqual(@as(usize, 2), count());
    try std.testing.expectEqual(components.FlowerType.tulip, get(3, 4).?);
    try std.testing.expectEqual(@as(?components.FlowerType, null), get(9, 9));
    try std.testing.expectEqual(@as(?components.FlowerType, null), get(-1, 200));
    set(-1, 200, .rose); // ignored
    try std.testing.expectEqual(@as(usize, 2), count());
    shift(1, 1);
    try std.testing.expectEqual(components.FlowerType.tulip, get(4, 5).?);
    try std.testing.expectEqual(components.FlowerType.rose, get(1, 1).?);
    try std.testing.expectEqual(@as(?components.FlowerType, null), get(3, 4));
    set(4, 5, null);
    try std.testing.expectEqual(@as(usize, 1), count());
    reset();
    try std.testing.expectEqual(@as(usize, 0), count());
}
