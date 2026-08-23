const rl = @import("raylib");
const text = @import("../text.zig");
const rg = @import("raygui");
const std = @import("std");
const theme = @import("../theme.zig");
const assets = @import("../assets.zig");
const locale = @import("../localization.zig");

pub const TitleScreenAction = enum {
    none,
    /// Resume the loaded save (or start fresh when there is none).
    play,
    /// Wipe progress and start over. Only emitted after a confirm click.
    new_game,
    quit,
    toggle_language,
};

/// "New Game" is destructive when a save exists, so the first click arms a
/// confirm state that expires after a few seconds.
var newGameArmedUntil: f64 = 0;
const NEW_GAME_CONFIRM_SECONDS: f64 = 4;

// Module-level texture storage for background bees
var beeTexture: ?rl.Texture = null;

pub fn init() void {
    if (beeTexture == null) {
        beeTexture = assets.loadTextureFromMemory(assets.bee_png) catch null;
    }
}

pub fn deinit() void {
    if (beeTexture) |tex| {
        rl.unloadTexture(tex);
        beeTexture = null;
    }
}

/// Draw title screen and return action taken by user
pub fn draw(screenWidth: f32, screenHeight: f32, hasSave: bool) TitleScreenAction {
    // Lazy init texture on first draw
    if (beeTexture == null) {
        init();
    }
    const centerX = screenWidth / 2;
    const centerY = screenHeight / 2;

    // Animated background - subtle pulsing
    const time = @as(f32, @floatCast(rl.getTime()));

    // Draw some decorative animated bees in background
    drawBackgroundBees(screenWidth, screenHeight, time);

    // Title text with shadow
    const titleText = "Buzzness Tycoon";
    const titleFontSize: i32 = 64;
    const titleWidth = text.measure(titleText, titleFontSize);
    const titleX = @as(i32, @intFromFloat(centerX)) - @divFloor(titleWidth, 2);
    const titleY = @as(i32, @intFromFloat(centerY)) - 150;

    // Shadow
    text.draw(titleText, titleX + 3, titleY + 3, titleFontSize, theme.CatppuccinMocha.Color.crust);
    // Main title with animated color
    const titlePulse = 0.8 + @sin(time * 2.0) * 0.2;
    const titleColor = rl.Color.init(
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.r)) * titlePulse),
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.g)) * titlePulse),
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.b)) * titlePulse),
        255,
    );
    text.draw(titleText, titleX, titleY, titleFontSize, titleColor);

    // Subtitle
    const subtitleText = locale.tr("A Bee Idle Game", "Um jogo idle de abelhas");
    const subtitleFontSize: i32 = 24;
    const subtitleWidth = text.measure(subtitleText, subtitleFontSize);
    const subtitleX = @as(i32, @intFromFloat(centerX)) - @divFloor(subtitleWidth, 2);
    text.draw(subtitleText, subtitleX, titleY + 70, subtitleFontSize, theme.CatppuccinMocha.Color.subtext0);

    // Buttons
    const buttonWidth: f32 = 270;
    const buttonHeight: f32 = 50;
    const buttonX = centerX - buttonWidth / 2;
    const buttonSpacing: f32 = 62;
    // Keep the column centred whether it has 3 or 4 buttons.
    const buttonCount: f32 = if (hasSave) 4 else 3;
    const buttonStartY = centerY + 5 - (buttonCount - 3) * buttonSpacing / 2;
    var by = buttonStartY;

    const now = rl.getTime();
    const armed = hasSave and now < newGameArmedUntil;

    // Continue / Play
    const playLabel = if (hasSave) locale.tr("Continue", "Continuar") else locale.tr("Play", "Jogar");
    if (rg.button(rl.Rectangle.init(buttonX, by, buttonWidth, buttonHeight), playLabel)) {
        newGameArmedUntil = 0;
        return .play;
    }
    by += buttonSpacing;

    // New Game (only when there is something to overwrite)
    if (hasSave) {
        const label = if (armed) locale.tr("Are you sure?", "Tem certeza?") else locale.tr("New Game", "Novo Jogo");
        if (armed) rg.setStyle(.button, .{ .control = .text_color_normal }, theme.CatppuccinMocha.Color.red.toInt());
        const clicked = rg.button(rl.Rectangle.init(buttonX, by, buttonWidth, buttonHeight), label);
        if (armed) rg.setStyle(.button, .{ .control = .text_color_normal }, theme.CatppuccinMocha.Color.text.toInt());
        if (clicked) {
            if (armed) {
                newGameArmedUntil = 0;
                return .new_game;
            }
            newGameArmedUntil = now + NEW_GAME_CONFIRM_SECONDS;
        }
        by += buttonSpacing;
    }

    if (rg.button(rl.Rectangle.init(buttonX, by, buttonWidth, buttonHeight), locale.languageButton())) {
        newGameArmedUntil = 0;
        return .toggle_language;
    }
    by += buttonSpacing;

    // Quit button
    if (rg.button(rl.Rectangle.init(buttonX, by, buttonWidth, buttonHeight), locale.tr("Quit", "Sair"))) {
        return .quit;
    }

    // Version text
    const versionText = "v0.2.0";
    const versionFontSize: i32 = 16;
    text.draw(versionText, 10, @as(i32, @intFromFloat(screenHeight)) - 26, versionFontSize, theme.CatppuccinMocha.Color.overlay0);

    // Controls hint
    const hintText = locale.tr("Alt+Enter: Toggle Fullscreen", "Alt+Enter: Alternar tela cheia");
    const hintWidth = text.measure(hintText, 16);
    text.draw(hintText, @as(i32, @intFromFloat(screenWidth)) - hintWidth - 10, @as(i32, @intFromFloat(screenHeight)) - 26, 16, theme.CatppuccinMocha.Color.overlay0);

    return .none;
}

/// Draw animated bees flying in the background using actual bee sprite
fn drawBackgroundBees(screenWidth: f32, screenHeight: f32, time: f32) void {
    const tex = beeTexture orelse return;

    const beeCount = 8;
    const beeScale: f32 = 0.4; // Scale down the bee sprite

    for (0..beeCount) |i| {
        const fi = @as(f32, @floatFromInt(i));
        const speed = 30.0 + fi * 10.0;
        const yOffset = fi * (screenHeight / @as(f32, @floatFromInt(beeCount)));

        // Each bee has different phase and path
        const phase = fi * 1.5;
        const x = @mod(time * speed + fi * 200.0, screenWidth + 100.0) - 50.0;
        const y = yOffset + @sin(time * 2.0 + phase) * 30.0;

        // Calculate rotation based on movement (slight wobble)
        const rotation = @sin(time * 4.0 + phase) * 10.0;

        // Draw bee sprite with transparency
        const texWidth = @as(f32, @floatFromInt(tex.width)) * beeScale;
        const texHeight = @as(f32, @floatFromInt(tex.height)) * beeScale;

        rl.drawTexturePro(
            tex,
            rl.Rectangle.init(0, 0, @floatFromInt(tex.width), @floatFromInt(tex.height)),
            rl.Rectangle.init(x, y, texWidth, texHeight),
            rl.Vector2.init(texWidth / 2, texHeight / 2),
            rotation,
            rl.Color.init(255, 255, 255, 120), // Semi-transparent
        );
    }
}
