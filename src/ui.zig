const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const theme = @import("theme.zig");

/// UI system for displaying game information and handling user interactions.
/// Uses raygui for buttons with Catppuccin Mocha theming.
pub const UI = struct {
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
