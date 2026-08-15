const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");

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

    pub fn draw(self: @This(), resources: *const Resources, bees: usize, beehiveFactor: f32) void {
        _ = self;

        const barX: f32 = 10;
        const barY: f32 = 10;

        if (config.honey_cap_enabled) {
            drawHoneyBar(resources, barX, barY);
        } else {
            drawHoneyText(resources, barX, barY);
        }

        // Rate line
        const rateText = rl.textFormat("+%.1f/s", .{resources.honeyPerSec});
        text.drawShadow(rateText, @intFromFloat(barX), 42, 20, theme.CatppuccinMocha.Color.green);

        // Draw bee count and beehive factor below
        text.drawShadow(rl.textFormat(locale.tr("Bees: %d", "Abelhas: %d"), .{bees}), 10, 68, 22, rl.Color.white);
        text.drawShadow(rl.textFormat(locale.tr("Honey Factor: %.1fx", "Fator de mel: %.1fx"), .{beehiveFactor}), 10, 96, 20, theme.CatppuccinMocha.Color.yellow);

        // Draw growth boost cooldown indicator
        drawGrowthBoostIndicator(resources, barX, 122);
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

    fn drawHoneyText(resources: *const Resources, x: f32, y: f32) void {
        var buf: [32]u8 = undefined;
        const s = format.formatShort(resources.honey, &buf);
        const honeyText = rl.textFormat(locale.tr("%s honey", "%s mel"), .{s.ptr});
        text.drawShadow(honeyText, @intFromFloat(x), @intFromFloat(y), 28, theme.CatppuccinMocha.Color.yellow);
    }

    fn drawGrowthBoostIndicator(resources: *const Resources, x: f32, y: f32) void {
        const indicatorWidth: f32 = 120;
        const indicatorHeight: f32 = 16;

        // Background
        rl.drawRectangle(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(indicatorWidth),
            @intFromFloat(indicatorHeight),
            theme.CatppuccinMocha.Color.surface0,
        );

        // Cooldown fill (fills up as cooldown progresses, full = ready)
        const readyPercent = 1.0 - resources.getCooldownPercent();
        const fillWidth = indicatorWidth * readyPercent;

        const fillColor = if (resources.canUseGrowthBoost())
            theme.CatppuccinMocha.Color.blue
        else
            theme.CatppuccinMocha.Color.surface2;

        rl.drawRectangle(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(fillWidth),
            @intFromFloat(indicatorHeight),
            fillColor,
        );

        // Border
        rl.drawRectangleLines(
            @intFromFloat(x),
            @intFromFloat(y),
            @intFromFloat(indicatorWidth),
            @intFromFloat(indicatorHeight),
            theme.CatppuccinMocha.Color.surface1,
        );

        // Text
        const statusText = if (resources.canUseGrowthBoost())
            locale.tr("GROW READY!", "CRESCER PRONTO!")
        else
            rl.textFormat(locale.tr("Grow: %.1fs", "Crescer: %.1fs"), .{resources.growthBoostCooldown});

        const statusColor = if (resources.canUseGrowthBoost())
            theme.CatppuccinMocha.Color.blue
        else
            theme.CatppuccinMocha.Color.subtext0;

        text.draw(statusText, @as(i32, @intFromFloat(x + 5)), @as(i32, @intFromFloat(y)), 16, statusColor);
    }
};
