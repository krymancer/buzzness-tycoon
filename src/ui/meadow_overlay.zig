//! Meadow-space overlays drawn over the world and under the HUD: the
//! cluster highlight and bonus label for the flower under the cursor, and
//! the planting brush's ghost cursor with its bonus preview.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const locale = @import("../localization.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const adjacency = @import("../adjacency.zig");
const plant_menu = @import("plant_menu.zig");
const Grid = @import("../grid.zig").Grid;
const Textures = @import("../textures.zig").Textures;
const Flowers = @import("../textures.zig").Flowers;

const OUTLINE = @import("hud.zig").OUTLINE;

// Tint only the diamond's top face; drawing the whole cube over the
// meadow made highlighted plans look like raised blocks.
fn tintTile(grid: *const Grid, pos: rl.Vector2, color: rl.Color) void {
    const w = 32 * grid.scale;
    const top = rl.Vector2.init(pos.x + w / 2, pos.y);
    const left = rl.Vector2.init(pos.x, pos.y + w / 4);
    const bottom = rl.Vector2.init(pos.x + w / 2, pos.y + w / 2);
    const right = rl.Vector2.init(pos.x + w, pos.y + w / 4);
    rl.drawTriangle(top, left, bottom, color);
    rl.drawTriangle(top, bottom, right, color);
    rl.drawLineEx(top, left, 1.5, color);
    rl.drawLineEx(left, bottom, 1.5, color);
    rl.drawLineEx(bottom, right, 1.5, color);
    rl.drawLineEx(right, top, 1.5, color);
}

/// Warm glow on every cell of cluster `id` (0 = none).
pub fn drawClusterHighlight(grid: *const Grid, id: u32) void {
    if (id == 0) return;
    for (0..grid.height) |j| {
        for (0..grid.width) |i| {
            if (adjacency.clusterIdAt(@intCast(i), @intCast(j)) != id) continue;
            const pos = utils.isoToXY(@floatFromInt(i), @floatFromInt(j), grid.tileWidth, grid.tileHeight, grid.offset.x, grid.offset.y, grid.scale);
            tintTile(grid, pos, rl.Color.init(166, 227, 161, 65));
        }
    }
}

/// "Cluster +50% · Pair +25% · Meadow x2 · Far +12%  = x3.36" into `buf`.
pub fn describe(b: adjacency.Bonus, buf: []u8) ?[:0]const u8 {
    var w: std.Io.Writer = .fixed(buf[0 .. buf.len - 1]);
    var first = true;
    const sep = "  ·  ";
    if (b.cluster) {
        w.print("{s} +{d}%", .{ locale.tr("Cluster", "Grupo"), @as(u32, @intFromFloat(@round((adjacency.CLUSTER_MUL - 1) * 100))) }) catch return null;
        first = false;
    }
    if (b.pair) {
        if (!first) w.writeAll(sep) catch return null;
        w.print("{s} +{d}%", .{ locale.tr("Pair", "Par"), @as(u32, @intFromFloat(@round((adjacency.PAIR_MUL - 1) * 100))) }) catch return null;
        first = false;
    }
    if (b.meadow) {
        if (!first) w.writeAll(sep) catch return null;
        w.print("{s} x{d}", .{ locale.tr("Meadow", "Campina"), @as(u32, @intFromFloat(adjacency.MEADOW_MUL)) }) catch return null;
        first = false;
    }
    if (b.rings > 0) {
        if (!first) w.writeAll(sep) catch return null;
        w.print("{s} +{d}%", .{ locale.tr("Far", "Longe"), @as(u32, @intFromFloat(@round(adjacency.GRADIENT_PER_RING * 100 * @as(f32, @floatFromInt(b.rings))))) }) catch return null;
        first = false;
    }
    if (first) return null;
    var mb: [16]u8 = undefined;
    const m = std.fmt.bufPrintZ(&mb, "{d:.2}", .{b.multiplier()}) catch "?";
    w.print("  =  x{s}", .{m}) catch return null;
    const n = w.end;
    buf[n] = 0;
    return buf[0..n :0];
}

fn tileTop(grid: *const Grid, x: i32, y: i32) rl.Vector2 {
    const pos = utils.isoToXY(@floatFromInt(x), @floatFromInt(y), grid.tileWidth, grid.tileHeight, grid.offset.x, grid.offset.y, grid.scale);
    return rl.Vector2.init(pos.x + 16 * grid.scale, pos.y - 24 * grid.scale);
}

/// Outlined label centred above a tile.
fn labelAbove(grid: *const Grid, x: i32, y: i32, line: [:0]const u8, size: i32, color: rl.Color, lift: f32, screenW: f32) void {
    const top = tileTop(grid, x, y);
    const w = text.measure(line, size);
    var lx = top.x - @as(f32, @floatFromInt(w)) / 2;
    lx = std.math.clamp(lx, 6, @max(6, screenW - @as(f32, @floatFromInt(w)) - 6));
    text.drawOutline(line, @intFromFloat(lx), @intFromFloat(top.y - lift), size, color, OUTLINE);
}

/// Bonus readout for the flower on (x, y) (nothing when it has none).
pub fn drawBonusLabel(grid: *const Grid, x: i32, y: i32, screenW: f32) void {
    const C = theme.CatppuccinMocha.Color;
    const b = adjacency.bonusAt(x, y);
    if (!b.any()) return;
    var buf: [128]u8 = undefined;
    const line = describe(b, &buf) orelse return;
    labelAbove(grid, x, y, line, 20, C.teal, 0, screenW);
}

pub const BrushCursor = struct {
    brush: ?Flowers,
    eraser: bool,
    remover: bool = false,
    x: i32,
    y: i32,
    /// Tile is a valid paint target (in bounds, not the hive).
    valid: bool,
    /// Something already grows there (the plan still applies).
    occupied: bool,
    planned: bool,
    cost: f32,
    afford: bool,
};

/// Ghost of the brush flower on the hovered tile with what it would earn.
pub fn drawBrushCursor(grid: *const Grid, textures: *const Textures, cur: BrushCursor, screenW: f32, time: f32) void {
    const C = theme.CatppuccinMocha.Color;
    const pos = utils.isoToXY(@floatFromInt(cur.x), @floatFromInt(cur.y), grid.tileWidth, grid.tileHeight, grid.offset.x, grid.offset.y, grid.scale);
    if (cur.eraser or cur.remover) {
        tintTile(grid, pos, rl.Color.init(243, 139, 168, if (cur.valid) 100 else 40));
        labelAbove(grid, cur.x, cur.y, if (cur.remover) locale.tr("Remove flower + plan", "Remover flor + plano") else locale.tr("Clear plan", "Limpar plano"), 20, C.red, 8, screenW);
        return;
    }
    const brush = cur.brush orelse return;
    const tint: rl.Color = if (!cur.valid) rl.Color.init(243, 139, 168, 120) else if (cur.afford) rl.Color.init(255, 255, 255, 170) else rl.Color.init(255, 255, 255, 110);
    tintTile(grid, pos, rl.Color.init(249, 226, 175, if (cur.valid) 80 else 30));
    if (!cur.occupied) {
        const tex = textures.getFlowerTexture(brush);
        const bob = 1.5 * @sin(time * 3.0) * grid.scale / 3.0;
        const s = 2.0 * grid.scale / 3.0;
        const dw = 32 * s;
        const dst = rl.Rectangle.init(pos.x + (32 * grid.scale - dw) / 2, pos.y + 32 * grid.scale * 0.25 - dw + bob, dw, dw);
        rl.drawTexturePro(tex, rl.Rectangle.init(128, 0, 32, 32), dst, rl.Vector2.init(0, 0), 0, tint);
    }

    var lbuf: [96]u8 = undefined;
    var cbuf: [32]u8 = undefined;
    const name = plant_menu.flowerName(brush);
    const what = if (!cur.valid)
        std.fmt.bufPrintZ(&lbuf, "{s}", .{locale.tr("can't plant here", "não dá para plantar aqui")}) catch name
    else if (cur.occupied)
        std.fmt.bufPrintZ(&lbuf, "{s} · {s}", .{ name, locale.tr("plan (replaces when it dies)", "plano (substitui quando morrer)") }) catch name
    else if (cur.afford)
        std.fmt.bufPrintZ(&lbuf, "{s} · {s} {s}", .{ name, format.formatShort(cur.cost, &cbuf), locale.tr("honey", "de mel") }) catch name
    else
        std.fmt.bufPrintZ(&lbuf, "{s} · {s} ({s})", .{ name, locale.tr("plan only", "só o plano"), format.formatShort(cur.cost, &cbuf) }) catch name;
    const color = if (!cur.valid) C.red else if (cur.afford or cur.occupied) C.yellow else C.peach;
    labelAbove(grid, cur.x, cur.y, what, 20, color, 20, screenW);

    if (cur.valid and !cur.occupied) {
        const ft = brush;
        var bbuf: [128]u8 = undefined;
        if (describe(adjacency.preview(cur.x, cur.y, ft), &bbuf)) |line| {
            labelAbove(grid, cur.x, cur.y, line, 18, C.teal, 0, screenW);
        }
    }
}
