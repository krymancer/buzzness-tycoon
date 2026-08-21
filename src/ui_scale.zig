//! Global UI scale. The whole frame is drawn through a Camera2D zoomed by
//! `factor`, and the mouse is scaled to match (rl.setMouseScale), so all game
//! and UI code keeps working in unscaled "logical" pixels — the classic
//! virtual-resolution trick. `factor` auto-fits the real screen size (fonts and
//! panels were designed for a ~1150x720 canvas and are unreadably small when
//! drawn 1:1 on large or Retina displays), multiplied by a user preference
//! adjustable with Cmd/Ctrl +/- and persisted in the save file.

const std = @import("std");
const rl = @import("raylib");

// The layout was designed around a ~1366x820 window; auto-fit against a
// slightly smaller reference so text gains a little size even at that window.
const REF_WIDTH: f32 = 1150;
const REF_HEIGHT: f32 = 720;

const USER_MIN: f32 = 0.6;
const USER_MAX: f32 = 2.5;

pub var factor: f32 = 1.0;

var userMul: f32 = 1.0;
var override: ?f32 = null; // BT_UI_SCALE: absolute factor, for reproducible dev captures

pub fn setOverride(value: ?f32) void {
    override = value;
}

pub fn user() f32 {
    return userMul;
}

pub fn setUser(value: f32) void {
    userMul = std.math.clamp(value, USER_MIN, USER_MAX);
}

pub fn adjustUser(delta: f32) void {
    setUser(userMul + delta);
}

pub fn resetUser() void {
    userMul = 1.0;
}

/// Recompute `factor` from the current window size and sync the mouse scale.
/// Call once per frame, before input handling.
///
/// Everything is based on the RENDER size (the actual framebuffer): with
/// window_highdpi on macOS Retina, raylib 6 sets the projection in framebuffer
/// pixels while getScreenWidth/getMousePosition stay in window points — drawing
/// "in points" only covered a quarter of the window. Fitting the render size
/// both fixes that and folds the DPI into the UI scale.
pub fn refresh() void {
    const renderW: f32 = @floatFromInt(rl.getRenderWidth());
    const renderH: f32 = @floatFromInt(rl.getRenderHeight());
    const screenW: f32 = @floatFromInt(rl.getScreenWidth());
    const screenH: f32 = @floatFromInt(rl.getScreenHeight());
    var f = override orelse blk: {
        // Never auto-shrink below the designed size; cap the auto growth so a
        // huge monitor still shows a sensible amount of meadow.
        const fit = @min(renderW / REF_WIDTH, renderH / REF_HEIGHT);
        break :blk std.math.clamp(fit, 1.0, 4.0) * userMul;
    };
    f = std.math.clamp(f, 0.75, 6.0);
    factor = f;
    // Mouse arrives in window points; map it into logical (render/factor) space.
    if (screenW > 0 and screenH > 0) {
        rl.setMouseScale(renderW / (screenW * factor), renderH / (screenH * factor));
    }
}

/// Logical screen size: what the game should treat as the window dimensions.
pub fn width() f32 {
    return @as(f32, @floatFromInt(rl.getRenderWidth())) / factor;
}

pub fn height() f32 {
    return @as(f32, @floatFromInt(rl.getRenderHeight())) / factor;
}

/// Wrap all drawing of a frame between begin()/end().
pub fn begin() void {
    rl.beginMode2D(.{
        .offset = rl.Vector2.init(0, 0),
        .target = rl.Vector2.init(0, 0),
        .rotation = 0,
        .zoom = factor,
    });
}

pub fn end() void {
    rl.endMode2D();
}
