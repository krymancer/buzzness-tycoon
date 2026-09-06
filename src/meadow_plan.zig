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

/// Integer line traversal: a brush stroke never skips cells between frames.
pub const Stroke = struct {
    x: i32,
    y: i32,
    end_x: i32,
    end_y: i32,
    dx: i32,
    dy: i32,
    sx: i32,
    sy: i32,
    err: i32,
    done: bool = false,

    pub fn init(from_x: i32, from_y: i32, x: i32, y: i32) Stroke {
        const start_x = if (from_x < 0 or from_y < 0) x else from_x;
        const start_y = if (from_x < 0 or from_y < 0) y else from_y;
        const dx: i32 = @intCast(@abs(x - start_x));
        const dy = -@as(i32, @intCast(@abs(y - start_y)));
        return .{ .x = start_x, .y = start_y, .end_x = x, .end_y = y, .dx = dx, .dy = dy, .sx = if (start_x < x) 1 else -1, .sy = if (start_y < y) 1 else -1, .err = dx + dy };
    }

    pub fn next(self: *Stroke) ?[2]i32 {
        if (self.done) return null;
        const cell = [2]i32{ self.x, self.y };
        if (self.x == self.end_x and self.y == self.end_y) {
            self.done = true;
            return cell;
        }
        const e = 2 * self.err;
        if (e >= self.dy) {
            self.err += self.dy;
            self.x += self.sx;
        }
        if (e <= self.dx) {
            self.err += self.dx;
            self.y += self.sy;
        }
        return cell;
    }
};

test "fast brush stroke fills gaps in either direction and starts fresh after release" {
    var stroke = Stroke.init(2, 3, 8, 3);
    var x: i32 = 2;
    while (stroke.next()) |cell| {
        try std.testing.expectEqual([2]i32{ x, 3 }, cell);
        x += 1;
    }
    try std.testing.expectEqual(@as(i32, 9), x);
    stroke = Stroke.init(8, 8, 2, 2);
    x = 8;
    while (stroke.next()) |cell| {
        try std.testing.expectEqual([2]i32{ x, x }, cell);
        x -= 1;
    }
    try std.testing.expectEqual(@as(i32, 1), x);
    stroke = Stroke.init(-1, -1, 5, 6);
    try std.testing.expectEqual([2]i32{ 5, 6 }, stroke.next().?);
    try std.testing.expect(stroke.next() == null);
}
