const rl = @import("raylib");
const rg = @import("raygui");
const theme = @import("../theme.zig");

pub const PauseMenuAction = enum {
    none,
    continue_game,
    exit_game,
};

/// Draw pause menu overlay. Returns action taken by user.
pub fn draw(screenWidth: f32, screenHeight: f32) PauseMenuAction {
    // Draw semi-transparent overlay
    rl.drawRectangle(0, 0, @intFromFloat(screenWidth), @intFromFloat(screenHeight), theme.CatppuccinMocha.Color.pauseOverlay);

    // Popup dimensions
    const popupWidth: f32 = 300;
    const popupHeight: f32 = 200;
    const popupX: f32 = (screenWidth - popupWidth) / 2;
    const popupY: f32 = (screenHeight - popupHeight) / 2;

    // Draw popup panel background
    rl.drawRectangleRounded(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        theme.CatppuccinMocha.Color.surface0,
    );
    rl.drawRectangleRoundedLines(
        rl.Rectangle.init(popupX, popupY, popupWidth, popupHeight),
        0.1,
        10,
        theme.CatppuccinMocha.Color.surface1,
    );

    // Title
    const titleText = "Paused";
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(rl.measureText(titleText, 32), 2);
    rl.drawText(titleText, titleX, @as(i32, @intFromFloat(popupY + 25)), 32, theme.CatppuccinMocha.Color.text);

    const buttonWidth: f32 = 200;
    const buttonHeight: f32 = 45;
    const buttonX = popupX + (popupWidth - buttonWidth) / 2;
    const buttonStartY = popupY + 80;
    const buttonSpacing: f32 = 55;

    // Continue button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), "Continue")) {
        return .continue_game;
    }

    // Exit button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), "Exit Game")) {
        return .exit_game;
    }

    return .none;
}
