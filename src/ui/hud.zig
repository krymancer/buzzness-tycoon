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
        const y0: f32 = 10;

        var hbuf: [32]u8 = undefined;
        var cbuf: [32]u8 = undefined;
        var fbuf: [32]u8 = undefined;
        var rbuf: [32]u8 = undefined;
        const hstr = format.formatShort(resources.honey, &hbuf);
        const cstr = format.formatShort(resources.honeyCapacity, &cbuf);
        const honeyText = rl.textFormat("%s", .{hstr.ptr});
        const capText = rl.textFormat("/ %s", .{cstr.ptr});
        // Same short treatment as honey; small values keep one decimal so
        // early-game x2.5 factors and sub-1/s rates still read exactly.
        const factorText = if (beehiveFactor < 1000.0)
            rl.textFormat("x%.1f", .{beehiveFactor})
        else
            rl.textFormat("x%s", .{format.formatShort(beehiveFactor, &fbuf).ptr});
        const rateText = if (resources.honeyPerSec < 1000.0)
            rl.textFormat("(+%.1f/s)", .{resources.honeyPerSec})
        else
            rl.textFormat("(+%s/s)", .{format.formatShort(resources.honeyPerSec, &rbuf).ptr});

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

        const full = resources.isAtCapacity();
        const textStartX: i32 = @intFromFloat(x0 + 2 + iconR * 2 + 12);
        var tx: i32 = textStartX;
        text.drawOutline(honeyText, tx, @intFromFloat(y0), bigSize, if (full) C.red else C.yellow, outline);
        tx += text.measure(honeyText, bigSize) + 8;
        if (config.honey_cap_enabled) {
            text.drawOutline(capText, tx, smallY, smallSize, if (full) C.red else C.subtext0, outline);
            tx += text.measure(capText, smallSize) + 12;
        }
        text.drawOutline(factorText, tx, smallY, smallSize, C.peach, outline);
        tx += text.measure(factorText, smallSize) + 10;
        text.drawOutline(rateText, tx, smallY, smallSize, C.green, outline);
        const lineEndX = tx + text.measure(rateText, smallSize);

        // Storage meter: a thin bar under the whole stat line. Turns red and
        // pulses at the cap so wasted honey is impossible to miss.
        if (config.honey_cap_enabled) {
            const barX: f32 = @floatFromInt(textStartX);
            const barW: f32 = @floatFromInt(lineEndX - textStartX);
            const barY: f32 = y0 + @as(f32, @floatFromInt(bigSize)) + 2;
            const barH: f32 = 6;
            rl.drawRectangleRounded(rl.Rectangle.init(barX - 1, barY - 1, barW + 2, barH + 2), 0.5, 4, outline);
            rl.drawRectangleRounded(rl.Rectangle.init(barX, barY, barW, barH), 0.5, 4, C.surface1);
            const pct = std.math.clamp(resources.getCapacityPercent(), 0, 1);
            const fillW = barW * pct;
            if (fillW > 2) {
                var fillColor = if (full) C.red else if (pct > 0.85) C.peach else C.yellow;
                if (full) {
                    const pulse = 0.7 + 0.3 * @sin(@as(f32, @floatCast(rl.getTime())) * 6.0);
                    fillColor.a = @intFromFloat(255.0 * pulse);
                }
                rl.drawRectangleRounded(rl.Rectangle.init(barX, barY, fillW, barH), 0.5, 4, fillColor);
            }
            if (full) {
                const fullText = locale.tr("STORAGE FULL", "ARMAZÉM CHEIO");
                text.drawOutline(fullText, lineEndX + 14, smallY, smallSize, C.red, outline);
            }
        }
    }
};
