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

    pub fn draw(self: @This(), honey: f32, bees: usize, beehiveFactor: f32, upgradeCost: f32) struct { buyBee: bool, upgradeBeehive: bool } {
        _ = self;
        rl.drawText(rl.textFormat("Honey: %.0f", .{honey}), 10, 10, 30, rl.Color.white);
        rl.drawText(rl.textFormat("Bees: %d", .{bees}), 10, 40, 30, rl.Color.white);
        rl.drawText(rl.textFormat("Beehive Factor: %.1fx", .{beehiveFactor}), 10, 70, 20, rl.Color.yellow);

        const buttonWidth: f32 = 220;
        const buttonHeight: f32 = 40;

        // Buy Bee button
        const buyBeeRect = rl.Rectangle.init(10, 100, buttonWidth, buttonHeight);
        const canAffordBee = honey >= 10.0;

        if (!canAffordBee) {
            rg.setState(@intFromEnum(rg.State.disabled));
        }

        const buyBeePressed = rg.button(buyBeeRect, "Buy Bee (10 Honey)");

        if (!canAffordBee) {
            rg.setState(@intFromEnum(rg.State.normal));
        }

        // Upgrade Beehive button
        const upgradeRect = rl.Rectangle.init(10, 150, buttonWidth, buttonHeight);
        const canAffordUpgrade = honey >= upgradeCost;

        if (!canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.disabled));
        }

        const upgradeText = rl.textFormat("Upgrade Beehive (%.0f)", .{upgradeCost});
        const upgradePressed = rg.button(upgradeRect, upgradeText);

        if (!canAffordUpgrade) {
            rg.setState(@intFromEnum(rg.State.normal));
        }

        return .{
            .buyBee = buyBeePressed and canAffordBee,
            .upgradeBeehive = upgradePressed and canAffordUpgrade,
        };
    }
};
