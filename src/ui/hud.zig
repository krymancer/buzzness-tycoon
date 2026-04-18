const rl = @import("raylib");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;

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
        rl.drawText(rateText, @intFromFloat(barX), 35, 16, theme.CatppuccinMocha.Color.green);

        // Draw bee count and beehive factor below
        rl.drawText(rl.textFormat("Bees: %d", .{bees}), 10, 57, 20, rl.Color.white);
        rl.drawText(rl.textFormat("Honey Factor: %.1fx", .{beehiveFactor}), 10, 82, 16, theme.CatppuccinMocha.Color.yellow);

        // Draw growth boost cooldown indicator
        drawGrowthBoostIndicator(resources, barX, 105);
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
        const textWidth = rl.measureText(honeyText, 16);
        const textX = @as(i32, @intFromFloat(barX + barWidth / 2)) - @divFloor(textWidth, 2);
        rl.drawText(honeyText, textX, @as(i32, @intFromFloat(barY + 2)), 16, rl.Color.white);

        if (resources.isAtCapacity()) {
            rl.drawText("STORAGE FULL!", @as(i32, @intFromFloat(barX + barWidth + 10)), @as(i32, @intFromFloat(barY + 2)), 16, theme.CatppuccinMocha.Color.red);
        }
    }

    fn drawHoneyText(resources: *const Resources, x: f32, y: f32) void {
        var buf: [32]u8 = undefined;
        const s = format.formatShort(resources.honey, &buf);
        const honeyText = rl.textFormat("%s honey", .{s.ptr});
        rl.drawText(honeyText, @intFromFloat(x), @intFromFloat(y), 20, theme.CatppuccinMocha.Color.yellow);
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
            "GROW READY!"
        else
            rl.textFormat("Grow: %.1fs", .{resources.growthBoostCooldown});

        const statusColor = if (resources.canUseGrowthBoost())
            theme.CatppuccinMocha.Color.blue
        else
            theme.CatppuccinMocha.Color.subtext0;

        rl.drawText(statusText, @as(i32, @intFromFloat(x + 5)), @as(i32, @intFromFloat(y + 1)), 14, statusColor);
    }
};
