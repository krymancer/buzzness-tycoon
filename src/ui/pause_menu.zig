const rl = @import("raylib");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const locale = @import("../localization.zig");
const widgets = @import("widgets.zig");

pub const PauseMenuAction = enum {
    none,
    continue_game,
    exit_game,
    options,
};

/// Draw pause menu overlay. Returns action taken by user.
pub fn draw(screenWidth: f32, screenHeight: f32) PauseMenuAction {
    // Draw semi-transparent overlay
    rl.drawRectangle(0, 0, @intFromFloat(screenWidth), @intFromFloat(screenHeight), theme.CatppuccinMocha.Color.pauseOverlay);

    // Popup dimensions
    const popupWidth: f32 = 360;
    const popupHeight: f32 = 290;
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
    const titleText = locale.tr("Paused", "Pausado");
    const titleX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(titleText, 32), 2);
    text.draw(titleText, titleX, @as(i32, @intFromFloat(popupY + 25)), 32, theme.CatppuccinMocha.Color.text);

    const saveHint = locale.tr("Progress saves automatically", "O progresso é salvo automaticamente");
    const saveHintX = @as(i32, @intFromFloat(popupX + popupWidth / 2)) - @divFloor(text.measure(saveHint, 17), 2);
    text.draw(saveHint, saveHintX, @as(i32, @intFromFloat(popupY + 68)), 17, theme.CatppuccinMocha.Color.green);

    const buttonWidth: f32 = 260;
    const buttonHeight: f32 = 48;
    const buttonX = popupX + (popupWidth - buttonWidth) / 2;
    const buttonStartY = popupY + 102;
    const buttonSpacing: f32 = 56;

    // Continue button
    if (widgets.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), locale.tr("Continue", "Continuar"))) {
        return .continue_game;
    }

    if (widgets.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), locale.tr("Options", "Opções"))) {
        return .options;
    }

    // Exit button
    if (widgets.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing * 2, buttonWidth, buttonHeight), locale.tr("Exit Game", "Sair do jogo"))) {
        return .exit_game;
    }

    return .none;
}
