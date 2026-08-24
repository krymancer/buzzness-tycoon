//! Global UI scale. The whole frame is drawn through a Camera2D zoomed by
//! `factor`, and the mouse is scaled to match (rl.setMouseScale), so all game
//! and UI code keeps working in unscaled "logical" pixels — the classic
//! virtual-resolution trick. `factor` auto-fits the real screen size (fonts and
//! panels were designed for a ~1150x720 canvas and are unreadably small when
//! drawn 1:1 on large or Retina displays), multiplied by a user preference
//! adjustable with Cmd/Ctrl +/- and persisted in the save file.

const std = @import("std");
const rl = @import("raylib");
const builtin = @import("builtin");

// The layout was designed around a ~1366x820 window; auto-fit against a
// slightly smaller reference so text gains a little size even at that window.
const REF_WIDTH: f32 = 1150;
const REF_HEIGHT: f32 = 720;

const USER_MIN: f32 = 0.6;
const USER_MAX: f32 = 2.5;

// The logical canvas never shrinks below this (fixed-size panels like the
// 520x540 options dialog must always fit on screen).
const MIN_LOGICAL_W: f32 = 660;
const MIN_LOGICAL_H: f32 = 600;

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
        var scaled = std.math.clamp(fit, 1.0, 4.0) * userMul;
        // Never let the logical canvas shrink below the fixed-panel minimum —
        // a big user scale on a small window would otherwise crop UI.
        scaled = @min(scaled, @min(renderW / MIN_LOGICAL_W, renderH / MIN_LOGICAL_H));
        break :blk scaled;
    };
    f = std.math.clamp(f, 0.75, 6.0);
    factor = f;
    // Map the mouse into logical (render/factor) space. Where the mouse
    // arrives differs per platform (see raylib's WindowSizeCallback): macOS
    // reports it in window points, so it must be scaled by render/screen
    // (2x on Retina); Windows/X11 report it in physical pixels already, so
    // applying that ratio there shoved the cursor right/down by the display
    // scaling (150% -> clicks landed 1.5x away). Exclusive fullscreen masked
    // this because raylib forces screen == render in that mode.
    if (screenW > 0 and screenH > 0) {
        const mouseToRender: f32 = if (builtin.os.tag == .macos) renderW / screenW else 1.0;
        const mouseToRenderY: f32 = if (builtin.os.tag == .macos) renderH / screenH else 1.0;
        rl.setMouseScale(mouseToRender / factor, mouseToRenderY / factor);
    }
}

/// Highest user multiplier that still changes anything on the current
/// window — past it, the minimum-logical-canvas clamp holds the factor.
/// The options slider uses this as its max so its range matches reality.
pub fn maxUser() f32 {
    const renderW: f32 = @floatFromInt(rl.getRenderWidth());
    const renderH: f32 = @floatFromInt(rl.getRenderHeight());
    if (renderW <= 0 or renderH <= 0) return USER_MAX;
    const fit = std.math.clamp(@min(renderW / REF_WIDTH, renderH / REF_HEIGHT), 1.0, 4.0);
    const cap = @min(renderW / MIN_LOGICAL_W, renderH / MIN_LOGICAL_H);
    return std.math.clamp(cap / fit, USER_MIN, USER_MAX);
}

/// Logical screen size: what the game should treat as the window dimensions.
pub fn width() f32 {
    return @as(f32, @floatFromInt(rl.getRenderWidth())) / factor;
}

pub fn height() f32 {
    return @as(f32, @floatFromInt(rl.getRenderHeight())) / factor;
}

/// Scissor in logical coordinates. raylib's scissor takes window ("screen")
/// pixels and scales them to the framebuffer itself, so convert
/// logical -> framebuffer (x factor) -> window (x screen/render).
pub fn beginScissor(x: f32, y: f32, w: f32, h: f32) void {
    const renderW: f32 = @floatFromInt(rl.getRenderWidth());
    const screenW: f32 = @floatFromInt(rl.getScreenWidth());
    const renderH: f32 = @floatFromInt(rl.getRenderHeight());
    const screenH: f32 = @floatFromInt(rl.getScreenHeight());
    const kx = factor * (if (renderW > 0) screenW / renderW else 1.0);
    const ky = factor * (if (renderH > 0) screenH / renderH else 1.0);
    rl.beginScissorMode(@intFromFloat(x * kx), @intFromFloat(y * ky), @intFromFloat(w * kx), @intFromFloat(h * ky));
}

pub fn endScissor() void {
    rl.endScissorMode();
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
