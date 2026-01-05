const rl = @import("raylib");
const rg = @import("raygui");
const std = @import("std");
const theme = @import("../theme.zig");
const assets = @import("../assets.zig");

pub const TitleScreenAction = enum {
    none,
    play,
    quit,
};

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
pub fn draw(screenWidth: f32, screenHeight: f32) TitleScreenAction {
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
    const titleWidth = rl.measureText(titleText, titleFontSize);
    const titleX = @as(i32, @intFromFloat(centerX)) - @divFloor(titleWidth, 2);
    const titleY = @as(i32, @intFromFloat(centerY)) - 150;

    // Shadow
    rl.drawText(titleText, titleX + 3, titleY + 3, titleFontSize, theme.CatppuccinMocha.Color.crust);
    // Main title with animated color
    const titlePulse = 0.8 + @sin(time * 2.0) * 0.2;
    const titleColor = rl.Color.init(
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.r)) * titlePulse),
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.g)) * titlePulse),
        @intFromFloat(@as(f32, @floatFromInt(theme.CatppuccinMocha.Color.yellow.b)) * titlePulse),
        255,
    );
    rl.drawText(titleText, titleX, titleY, titleFontSize, titleColor);

    // Subtitle
    const subtitleText = "A Bee Idle Game";
    const subtitleFontSize: i32 = 24;
    const subtitleWidth = rl.measureText(subtitleText, subtitleFontSize);
    const subtitleX = @as(i32, @intFromFloat(centerX)) - @divFloor(subtitleWidth, 2);
    rl.drawText(subtitleText, subtitleX, titleY + 70, subtitleFontSize, theme.CatppuccinMocha.Color.subtext0);

    // Buttons
    const buttonWidth: f32 = 200;
    const buttonHeight: f32 = 50;
    const buttonX = centerX - buttonWidth / 2;
    const buttonStartY = centerY + 20;
    const buttonSpacing: f32 = 70;

    // Play button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY, buttonWidth, buttonHeight), "Play")) {
        return .play;
    }

    // Quit button
    if (rg.button(rl.Rectangle.init(buttonX, buttonStartY + buttonSpacing, buttonWidth, buttonHeight), "Quit")) {
        return .quit;
    }

    // Version text
    const versionText = "v0.1.0";
    const versionFontSize: i32 = 16;
    rl.drawText(versionText, 10, @as(i32, @intFromFloat(screenHeight)) - 26, versionFontSize, theme.CatppuccinMocha.Color.overlay0);

    // Controls hint
    const hintText = "Alt+Enter: Toggle Fullscreen";
    const hintWidth = rl.measureText(hintText, 16);
    rl.drawText(hintText, @as(i32, @intFromFloat(screenWidth)) - hintWidth - 10, @as(i32, @intFromFloat(screenHeight)) - 26, 16, theme.CatppuccinMocha.Color.overlay0);

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
