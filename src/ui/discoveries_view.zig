//! Full-screen Discoveries book: every achievement as a card (silhouette
//! until earned, hidden ones show as "???"), with progress bars for the
//! milestone ones, and the profile's lifetime counters along the bottom.
//! Mirrors the Steam list 1:1 so goals are visible without the overlay.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const locale = @import("../localization.zig");
const format = @import("../format.zig");
const icons = @import("icons.zig");
const input = @import("../input.zig");
const widgets = @import("widgets.zig");
const clock = @import("../clock.zig");
const achievements = @import("../achievements.zig");

pub const Action = enum { none, close };

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    tracker: *const achievements.Tracker,
    stats: *const achievements.Stats,
};

const MAX_CONTENT_W: f32 = 1400;
var scroll: f32 = 0;
const ui_scale = @import("../ui_scale.zig");

fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const lerp = struct {
        fn f(x: u8, y: u8, k: f32) u8 {
            return @intFromFloat(@as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(x))) * k);
        }
    }.f;
    return rl.Color.init(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), 255);
}

/// Draw a line at `size`, stepping the font down (to a floor of 10) until it fits.
fn drawFitted(line: [:0]const u8, x: i32, y: i32, size: i32, maxW: i32, color: rl.Color) void {
    var s = size;
    while (s > 10 and text.measure(line, s) > maxW) s -= 1;
    text.draw(line, x, y + @divFloor(size - s, 2), s, color);
}

pub fn draw(ctx: Context) Action {
    const C = theme.CatppuccinMocha.Color;
    const now: f32 = @floatCast(clock.time());
    const W = ctx.screenWidth;
    const H = ctx.screenHeight;
    input.registerBlock(rl.Rectangle.init(0, 0, W, H));

    rl.drawRectangle(0, 0, @intFromFloat(W), @intFromFloat(H), C.mantle);
    const breathe = 0.5 + 0.5 * @sin(now * 1.6);
    rl.drawRectangle(0, 0, @intFromFloat(W), 3, lerpColor(C.yellow, C.peach, breathe));

    const title = locale.tr("Discoveries", "Descobertas");
    text.draw(title, @as(i32, @intFromFloat(W / 2)) - @divFloor(text.measure(title, 32), 2), 10, 32, C.yellow);

    const found = ctx.tracker.unlockedCount();
    const countLabel = rl.textFormat(locale.tr("%d/%d found", "%d/%d encontradas"), .{ @as(c_int, @intCast(found)), @as(c_int, achievements.COUNT) });
    const cw: f32 = @floatFromInt(text.measure(countLabel, 19));
    const pill = rl.Rectangle.init(W - 16 - (cw + 28), 14, cw + 28, 36);
    rl.drawRectangleRounded(pill, 0.5, 8, C.surface0);
    rl.drawRectangleRoundedLinesEx(pill, 0.5, 8, 1, C.surface2);
    text.draw(countLabel, @intFromFloat(pill.x + 14), @intFromFloat(pill.y + 8), 19, C.subtext1);

    // Cards.
    const contentW: f32 = @min(W - 40, MAX_CONTENT_W);
    const contentX = (W - contentW) / 2;
    const contentY: f32 = 64;
    const statsH: f32 = 44;
    const contentH = H - contentY - 78 - statsH;
    const cols: usize = if (contentW >= 1000) 3 else 2;
    const gap: f32 = 12;
    const cardW = (contentW - gap * @as(f32, @floatFromInt(cols - 1))) / @as(f32, @floatFromInt(cols));
    const rows: usize = (achievements.COUNT + cols - 1) / cols;
    const cardH: f32 = 86;
    const totalH = @as(f32, @floatFromInt(rows)) * (cardH + gap) - gap;
    scroll = std.math.clamp(scroll - rl.getMouseWheelMoveV().y * 40 + input.cameraPan().y, 0, @max(0, totalH - contentH));
    ui_scale.beginScissor(contentX, contentY, contentW, contentH);
    const compact = cardH < 66;

    for (&achievements.DEFS, 0..) |*d, i| {
        const col = i % cols;
        const row = i / cols;
        const x = contentX + @as(f32, @floatFromInt(col)) * (cardW + gap);
        const y = contentY + @as(f32, @floatFromInt(row)) * (cardH + gap) - scroll;
        if (y + cardH < contentY or y > contentY + contentH) continue;
        const rect = rl.Rectangle.init(x, y, cardW, cardH);
        const unlocked = ctx.tracker.isUnlocked(d.id);
        const secret = d.hidden and !unlocked;

        rl.drawRectangleRounded(rect, 0.12, 6, if (unlocked) C.surface0 else C.base);
        rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, if (unlocked) 2 else 1, if (unlocked) C.yellow else C.surface1);

        // Badge: crown when found, a dim disc with "?" otherwise.
        const badge: f32 = @min(44, cardH - 12);
        const bx = x + 10;
        const by = y + (cardH - badge) / 2;
        rl.drawRectangleRounded(rl.Rectangle.init(bx, by, badge, badge), 0.3, 6, C.mantle);
        if (unlocked) {
            icons.drawCrown(bx + badge / 2, by + badge / 2, badge * 0.55, C.yellow, C.pink);
        } else {
            rl.drawCircleV(rl.Vector2.init(bx + badge / 2, by + badge / 2), badge * 0.3, C.surface1);
            const q = "?";
            text.draw(q, @as(i32, @intFromFloat(bx + badge / 2)) - @divFloor(text.measure(q, 18), 2), @intFromFloat(by + badge / 2 - 10), 18, C.overlay0);
        }

        const tx: i32 = @intFromFloat(bx + badge + 10);
        const avail: i32 = @intFromFloat(x + cardW - 12 - (bx + badge + 10));
        const nameY: f32 = if (compact) 5 else 9;
        const descY: f32 = if (compact) 24 else 32;
        const nameSize: i32 = if (compact) 16 else 18;
        const descSize: i32 = if (compact) 12 else 13;
        const nameText = if (secret) "???" else achievements.name(d.id);
        const descText = if (secret) locale.tr("Hidden until you stumble on it.", "Escondida até você tropeçar nela.") else achievements.description(d.id);
        drawFitted(nameText, tx, @intFromFloat(y + nameY), nameSize, avail, if (unlocked) C.yellow else C.subtext1);
        drawFitted(descText, tx, @intFromFloat(y + descY), descSize, avail, if (unlocked) C.subtext0 else C.overlay1);

        // Progress strip for milestone achievements still in progress.
        if (!unlocked and !secret) {
            if (d.progress) |p| {
                const have = ctx.stats.get(p.stat);
                const frac: f32 = @floatCast(std.math.clamp(have / p.target, 0, 1));
                const sx = @as(f32, @floatFromInt(tx));
                const sw = @as(f32, @floatFromInt(avail));
                const sy = y + cardH - 9;
                rl.drawRectangleRounded(rl.Rectangle.init(sx, sy, sw, 4), 0.5, 4, C.surface1);
                if (frac > 0) rl.drawRectangleRounded(rl.Rectangle.init(sx, sy, sw * frac, 4), 0.5, 4, C.teal);
                var b1: [32]u8 = undefined;
                var b2: [32]u8 = undefined;
                const prog = rl.textFormat("%s / %s", .{ format.formatShort(have, &b1).ptr, format.formatShort(p.target, &b2).ptr });
                const pw = text.measure(prog, 11);
                text.draw(prog, @as(i32, @intFromFloat(x + cardW - 12)) - pw, @intFromFloat(y + nameY + 3), 11, C.teal);
            }
        }
    }

    ui_scale.endScissor();

    // Lifetime counters.
    {
        const sy = contentY + contentH + 10;
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        var b3: [32]u8 = undefined;
        var b4: [32]u8 = undefined;
        var b5: [32]u8 = undefined;
        const line = rl.textFormat(
            locale.tr("Lifetime honey %s   ·   Prestiges %s   ·   SUPER flowers merged %s   ·   Rot cleared %s   ·   Most bees alive %s", "Mel na vida %s   ·   Prestígios %s   ·   SUPERflores fundidas %s   ·   Podres limpas %s   ·   Máx. de abelhas vivas %s"),
            .{
                format.formatShort(ctx.stats.lifetimeHoney, &b1).ptr,
                format.formatShort(@floatFromInt(ctx.stats.prestigeCount), &b2).ptr,
                format.formatShort(@floatFromInt(ctx.stats.superFlowersMerged), &b3).ptr,
                format.formatShort(@floatFromInt(ctx.stats.rottenCleared), &b4).ptr,
                format.formatShort(@floatFromInt(ctx.stats.maxBeesAlive), &b5).ptr,
            },
        );
        drawFitted(line, @intFromFloat(contentX), @intFromFloat(sy + 8), 15, @intFromFloat(contentW), C.subtext0);
    }

    var action: Action = .none;
    const closeW: f32 = 140;
    const closeH: f32 = 44;
    if (widgets.button(rl.Rectangle.init(W - closeW - 14, H - closeH - 14, closeW, closeH), locale.tr("Close", "Fechar"))) {
        action = .close;
    }
    const hint = locale.tr("Scroll / right stick to browse", "Role / stick direito para navegar");
    text.draw(hint, 18, @intFromFloat(H - closeH - 14 + 14), 14, C.overlay1);
    return action;
}
