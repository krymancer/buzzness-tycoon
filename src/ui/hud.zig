const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");
const icons = @import("icons.zig");

/// Outline colour for HUD text floating over the meadow (action_hud matches).
pub const OUTLINE = rl.Color.init(24, 24, 37, 235);

/// HUD system for displaying game information: the honey stat block in the
/// top-left corner.
pub const Hud = struct {
    pub fn init() @This() {
        // Apply the Catppuccin Mocha theme
        theme.applyCatppuccinMochaTheme();

        return .{};
    }

    pub fn deinit(self: @This()) void {
        _ = self;
    }

    /// Two outlined stat lines over the meadow, no backing panel:
    ///
    ///   🍯 1250 / 5K            amount (big) and storage cap
    ///   ▬▬▬▬▬▬▬▬▬▬▬▬            storage meter
    ///   +12.3/s  hive x4.0  🌙 night x0.50
    ///
    /// Honey per second is the number players watch, so it leads the second
    /// line at the same weight as the cap; the hive multiplier is labelled,
    /// and while it's night a moon chip shows the current night multiplier
    /// so the dip in income has a visible cause.
    pub fn draw(self: @This(), resources: *const Resources, beehiveFactor: f32, nightFactor: f32, nightMul: f32) void {
        _ = self;
        const C = theme.CatppuccinMocha.Color;
        const outline = OUTLINE;

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
            rl.textFormat("%s x%.1f", .{ locale.tr("hive", "colmeia").ptr, beehiveFactor })
        else
            rl.textFormat("%s x%s", .{ locale.tr("hive", "colmeia").ptr, format.formatShort(beehiveFactor, &fbuf).ptr });
        const rateText = if (resources.honeyPerSec < 1000.0)
            rl.textFormat("+%.1f/s", .{resources.honeyPerSec})
        else
            rl.textFormat("+%s/s", .{format.formatShort(resources.honeyPerSec, &rbuf).ptr});

        const bigSize: i32 = 40;
        const capSize: i32 = 24;
        const rateSize: i32 = 26;
        const chipSize: i32 = 20;
        // Digits at size 40 have their optical middle around y0+20; centre
        // the icon and the cap on that line.
        const midY: f32 = y0 + 20;
        const capY: i32 = @as(i32, @intFromFloat(midY)) - @divFloor(capSize, 2) - 1;

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
            text.drawOutline(capText, tx, capY, capSize, if (full) C.red else C.subtext0, outline);
            tx += text.measure(capText, capSize) + 12;
        }
        const line1EndX = tx;

        // Storage meter: a thin bar under the amount. Turns red and pulses
        // at the cap so wasted honey is impossible to miss.
        var line2Y: f32 = y0 + @as(f32, @floatFromInt(bigSize)) + 4;
        if (config.honey_cap_enabled) {
            const barX: f32 = @floatFromInt(textStartX);
            const barW: f32 = @max(120, @as(f32, @floatFromInt(line1EndX - textStartX)) - 12);
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
            line2Y = barY + barH + 6;
        }

        // Second line: rate, labelled hive factor, night chip, full warning.
        const ly: i32 = @intFromFloat(line2Y);
        const chipY: i32 = ly + @divFloor(rateSize - chipSize, 2);
        tx = textStartX;
        text.drawOutline(rateText, tx, ly, rateSize, C.green, outline);
        tx += text.measure(rateText, rateSize) + 14;
        text.drawOutline(factorText, tx, chipY, chipSize, C.peach, outline);
        tx += text.measure(factorText, chipSize) + 14;

        if (nightFactor > 0.01) {
            // Moon disc with craters (same motif as the Night Shift node).
            const mcx: f32 = @as(f32, @floatFromInt(tx)) + 8;
            const mcy: f32 = @as(f32, @floatFromInt(chipY)) + @as(f32, @floatFromInt(chipSize)) / 2 + 1;
            rl.drawCircleV(rl.Vector2.init(mcx, mcy), 8.5, outline);
            rl.drawCircleV(rl.Vector2.init(mcx, mcy), 7, C.lavender);
            rl.drawCircleV(rl.Vector2.init(mcx - 2, mcy - 1.5), 1.5, C.overlay1);
            rl.drawCircleV(rl.Vector2.init(mcx + 2, mcy + 1.5), 2, C.overlay1);
            rl.drawCircleV(rl.Vector2.init(mcx + 0.5, mcy - 4), 1.2, C.overlay1);
            tx += 20;
            const nightText = rl.textFormat("%s x%.2f", .{ locale.tr("night", "noite").ptr, nightMul });
            text.drawOutline(nightText, tx, chipY, chipSize, if (nightMul >= 0.995) C.green else C.lavender, outline);
            tx += text.measure(nightText, chipSize) + 14;
        }

        if (config.honey_cap_enabled and full) {
            const fullText = locale.tr("STORAGE FULL", "ARMAZÉM CHEIO");
            text.drawOutline(fullText, tx, chipY, chipSize, C.red, outline);
        }
    }
};
