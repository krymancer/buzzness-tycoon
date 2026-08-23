const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");
const icons = @import("icons.zig");

/// HUD system for displaying game information.
/// Shows honey count with storage bar, bee count, beehive factor, and growth boost cooldown.
pub const Hud = struct {
    pub fn init() @This() {
        // Apply the Catppuccin Mocha theme
        theme.applyCatppuccinMochaTheme();

        return .{};
    }

    pub fn deinit(self: @This()) void {
        _ = self;
    }

    /// One condensed, outlined stat line: `🍯 1250 x4 (+12/s)` — amount,
    /// beehive factor, rate. Outlined glyphs read over any background, so no
    /// backing panel is needed.
    pub fn draw(self: @This(), resources: *const Resources, beehiveFactor: f32) void {
        _ = self;
        const C = theme.CatppuccinMocha.Color;
        const outline = rl.Color.init(24, 24, 37, 235);

        const x0: f32 = 12;
        var y0: f32 = 10;
        if (config.honey_cap_enabled) {
            drawHoneyBar(resources, x0, y0);
            y0 += 30;
        }

        var hbuf: [32]u8 = undefined;
        const hstr = format.formatShort(resources.honey, &hbuf);
        const honeyText = rl.textFormat("%s", .{hstr.ptr});
        const factorText = rl.textFormat("x%.1f", .{beehiveFactor});
        const rateText = rl.textFormat("(+%.1f/s)", .{resources.honeyPerSec});

        const bigSize: i32 = 40;
        const smallSize: i32 = 24;
        // Digits at size 40 have their optical middle around y0+20; centre
        // the icon and the small segments on that line.
        const midY: f32 = y0 + 20;
        const smallY: i32 = @as(i32, @intFromFloat(midY)) - @divFloor(smallSize, 2) - 1;

        // Drop height is ~2.8r; r=8 keeps it at digit height (~22px) rather
        // than towering over the number.
        const iconR: f32 = 8;
        // The drop's optical centre sits 0.65r above its bead centre.
        const iconCy = midY + iconR * 0.65;
        icons.drawHoneyDropOutlined(x0 + 2 + iconR, iconCy, iconR, C.yellow, outline);
        rl.drawCircle(@intFromFloat(x0 + 2 + iconR - 2.5), @intFromFloat(iconCy - 2.5), 2.5, rl.Color.init(255, 250, 220, 200));

        var tx: i32 = @intFromFloat(x0 + 2 + iconR * 2 + 12);
        text.drawOutline(honeyText, tx, @intFromFloat(y0), bigSize, C.yellow, outline);
        tx += text.measure(honeyText, bigSize) + 10;
        text.drawOutline(factorText, tx, smallY, smallSize, C.peach, outline);
        tx += text.measure(factorText, smallSize) + 10;
        text.drawOutline(rateText, tx, smallY, smallSize, C.green, outline);
    }

    fn drawHoneyBar(resources: *const Resources, barX: f32, barY: f32) void {
        const barWidth: f32 = 200;
        const barHeight: f32 = 20;

        rl.drawRectangle(
            @intFromFloat(barX),
            @intFromFloat(barY),
            @intFromFloat(barWidth),
            @intFromFloat(barHeight),
            theme.CatppuccinMocha.Color.surface0,
        );

        const fillPercent = resources.getCapacityPercent();
        const fillWidth = barWidth * fillPercent;

        rl.drawRectangle(
            @intFromFloat(barX),
            @intFromFloat(barY),
            @intFromFloat(fillWidth),
            @intFromFloat(barHeight),
            theme.CatppuccinMocha.Color.yellow,
        );

        rl.drawRectangleLines(
            @intFromFloat(barX),
            @intFromFloat(barY),
            @intFromFloat(barWidth),
            @intFromFloat(barHeight),
            theme.CatppuccinMocha.Color.surface1,
        );

        var hbuf: [32]u8 = undefined;
        var cbuf: [32]u8 = undefined;
        const hstr = format.formatShort(resources.honey, &hbuf);
        const cstr = format.formatShort(resources.honeyCapacity, &cbuf);
        const honeyText = rl.textFormat("%s / %s", .{ hstr.ptr, cstr.ptr });
        const textWidth = text.measure(honeyText, 16);
        const textX = @as(i32, @intFromFloat(barX + barWidth / 2)) - @divFloor(textWidth, 2);
        text.draw(honeyText, textX, @as(i32, @intFromFloat(barY + 2)), 16, rl.Color.white);

        if (resources.isAtCapacity()) {
            text.draw(locale.tr("STORAGE FULL!", "ARMAZÉM CHEIO!"), @as(i32, @intFromFloat(barX + barWidth + 10)), @as(i32, @intFromFloat(barY + 2)), 18, theme.CatppuccinMocha.Color.red);
        }
    }
};
