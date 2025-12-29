const rl = @import("raylib");
const std = @import("std");
const theme = @import("../theme.zig");

/// HUD system for displaying game information.
/// Shows honey count, bee count, and beehive factor.
pub const Hud = struct {
    pub fn init() @This() {
        // Apply the Catppuccin Mocha theme
        theme.applyCatppuccinMochaTheme();

        return .{};
    }

    pub fn deinit(self: @This()) void {
        _ = self;
    }

    pub fn draw(self: @This(), honey: f32, bees: usize, beehiveFactor: f32) void {
        _ = self;
        rl.drawText(rl.textFormat("Honey: %.0f", .{honey}), 10, 10, 30, rl.Color.white);
        rl.drawText(rl.textFormat("Bees: %d", .{bees}), 10, 40, 30, rl.Color.white);
        rl.drawText(rl.textFormat("Beehive Factor: %.1fx", .{beehiveFactor}), 10, 70, 20, rl.Color.yellow);
    }
};
