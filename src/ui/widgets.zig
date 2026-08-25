//! Immediate-mode button, slider, and segment drawn in a chunky pixel-art
//! style (2px black-ish outline with notched corners, flat face, darker
//! bottom lip) to match the Kenney prompt icons. These read the unified
//! input layer (mouse or gamepad virtual cursor) and register themselves as
//! d-pad hotspots, which raygui — polling the raw mouse internally — could
//! not do.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const input = @import("../input.zig");

const BORDER: f32 = 2;
const LIP: f32 = 4;

fn darken(c: rl.Color, k: f32) rl.Color {
    return rl.Color.init(
        @intFromFloat(@as(f32, @floatFromInt(c.r)) * k),
        @intFromFloat(@as(f32, @floatFromInt(c.g)) * k),
        @intFromFloat(@as(f32, @floatFromInt(c.b)) * k),
        c.a,
    );
}

/// Pixel-key panel: notched-corner outline, flat face, darker bottom lip.
/// `pressed` drops the lip so the key reads as pushed in.
fn pixelPanel(rect: rl.Rectangle, face: rl.Color, pressed: bool) void {
    const outline = theme.CatppuccinMocha.Color.crust;
    const x = rect.x;
    const y = rect.y;
    const w = rect.width;
    const h = rect.height;
    // Outline strips (leave the 2x2 corners open — pixel "rounding").
    rl.drawRectangleRec(rl.Rectangle.init(x + BORDER, y, w - 2 * BORDER, BORDER), outline);
    rl.drawRectangleRec(rl.Rectangle.init(x + BORDER, y + h - BORDER, w - 2 * BORDER, BORDER), outline);
    rl.drawRectangleRec(rl.Rectangle.init(x, y + BORDER, BORDER, h - 2 * BORDER), outline);
    rl.drawRectangleRec(rl.Rectangle.init(x + w - BORDER, y + BORDER, BORDER, h - 2 * BORDER), outline);
    // Face and bottom lip.
    rl.drawRectangleRec(rl.Rectangle.init(x + BORDER, y + BORDER, w - 2 * BORDER, h - 2 * BORDER), face);
    if (!pressed) {
        rl.drawRectangleRec(rl.Rectangle.init(x + BORDER, y + h - BORDER - LIP, w - 2 * BORDER, LIP), darken(face, 0.72));
    }
}

pub const ButtonOpts = struct {
    enabled: bool = true,
    textColor: ?rl.Color = null,
    fontSize: i32 = 19,
};

/// Yellow pixel-key action button. True when clicked.
pub fn button(rect: rl.Rectangle, label: [:0]const u8) bool {
    return buttonEx(rect, label, .{});
}

pub fn buttonEx(rect: rl.Rectangle, label: [:0]const u8, opts: ButtonOpts) bool {
    const C = theme.CatppuccinMocha.Color;
    if (opts.enabled) input.registerHotspot(rect);

    const hovered = opts.enabled and rl.checkCollisionPointRec(input.pointerPos(), rect);
    const pressed = hovered and input.confirmDown();

    const face = if (!opts.enabled) C.surface0 else if (hovered) C.peach else C.yellow;
    const labelColor = if (!opts.enabled) C.subtext0 else opts.textColor orelse C.base;

    const off: f32 = if (pressed) 2 else 0;
    const r = rl.Rectangle.init(rect.x, rect.y + off, rect.width, rect.height - off);
    pixelPanel(r, face, pressed);

    const tw = text.measure(label, opts.fontSize);
    const tx = @as(i32, @intFromFloat(r.x + r.width / 2)) - @divFloor(tw, 2);
    const ty = @as(i32, @intFromFloat(r.y + (r.height - LIP - @as(f32, @floatFromInt(opts.fontSize))) / 2 + 1));
    text.draw(label, tx, ty, opts.fontSize, labelColor);

    const clicked = hovered and opts.enabled and input.confirmPressed();
    if (clicked) input.consumeConfirm();
    return clicked;
}

/// Segmented toggle chip (used for option rows). True when clicked.
pub fn segment(rect: rl.Rectangle, label: [:0]const u8, selected: bool) bool {
    const C = theme.CatppuccinMocha.Color;
    input.registerHotspot(rect);
    const hovered = rl.checkCollisionPointRec(input.pointerPos(), rect);
    const face = if (selected) C.yellow else if (hovered) C.surface2 else C.surface1;
    pixelPanel(rect, face, false);
    const tw = text.measure(label, 17);
    text.draw(
        label,
        @as(i32, @intFromFloat(rect.x + rect.width / 2)) - @divFloor(tw, 2),
        @as(i32, @intFromFloat(rect.y + (rect.height - LIP - 17) / 2 + 1)),
        17,
        if (selected) C.base else C.text,
    );
    const clicked = hovered and input.confirmPressed();
    if (clicked) input.consumeConfirm();
    return clicked;
}

// The slider being dragged, so the handle follows the pointer even when it
// slips off the track vertically mid-drag. Identified by its value pointer.
var activeSlider: ?*f32 = null;

/// Horizontal pixel slider: outlined track + yellow fill + square knob,
/// value label on the right. Updates `value` in place; true when it changed.
///
/// Gamepad drags adjust by left-stick rate and pin the cursor to the knob:
/// mapping the virtual cursor's absolute position would feed back on itself
/// when the slider changes the UI scale (the panel moves in logical space
/// while the OS-derived mouse position stays consistent — the virtual cursor
/// doesn't), slamming the value to an extreme.
pub fn slider(rect: rl.Rectangle, rightLabel: ?[:0]const u8, value: *f32, min: f32, max: f32) bool {
    const C = theme.CatppuccinMocha.Color;
    input.registerHotspot(rect);

    const mouse = input.pointerPos();
    // Generous grab area so the small knob isn't fiddly.
    const grabRect = rl.Rectangle.init(rect.x - 6, rect.y - 6, rect.width + 12, rect.height + 12);
    const hovered = rl.checkCollisionPointRec(mouse, grabRect);

    if (activeSlider == value and !input.confirmDown()) activeSlider = null;
    if (hovered and input.confirmPressed()) {
        activeSlider = value;
        input.consumeConfirm();
    }
    const dragging = activeSlider == value;

    const old = value.*;
    const midY = rect.y + rect.height / 2;
    if (dragging) {
        if (input.gamepadActive()) {
            const ax = input.menuStickX();
            if (ax != 0) {
                value.* = std.math.clamp(value.* + ax * (max - min) * rl.getFrameTime() * 0.8, min, max);
            }
            const frac0 = std.math.clamp((value.* - min) / (max - min), 0, 1);
            input.warpCursor(rl.Vector2.init(rect.x + rect.width * frac0, midY));
        } else {
            const frac0 = std.math.clamp((mouse.x - rect.x) / rect.width, 0, 1);
            value.* = min + frac0 * (max - min);
        }
    }

    // Track, fill, knob
    const trackH: f32 = 12;
    const track = rl.Rectangle.init(rect.x, midY - trackH / 2, rect.width, trackH);
    pixelPanel(track, C.surface1, true);
    const frac = std.math.clamp((value.* - min) / (max - min), 0, 1);
    const fillW = (track.width - 2 * BORDER) * frac;
    if (fillW > 1) {
        rl.drawRectangleRec(rl.Rectangle.init(track.x + BORDER, track.y + BORDER, fillW, trackH - 2 * BORDER), C.yellow);
    }
    const knob: f32 = 18;
    const hx = rect.x + rect.width * frac - knob / 2;
    pixelPanel(rl.Rectangle.init(hx, midY - knob / 2, knob, knob), if (dragging) C.peach else C.yellow, false);

    if (rightLabel) |label| {
        text.draw(label, @intFromFloat(rect.x + rect.width + 14), @intFromFloat(midY - 9), 17, C.text);
    }

    return @abs(value.* - old) > 0.0001;
}
