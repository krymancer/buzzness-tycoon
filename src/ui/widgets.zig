//! Immediate-mode button and slider drawn in the game's Catppuccin style.
//! Replaces raygui's widgets: these read the unified input layer (mouse or
//! gamepad virtual cursor) and register themselves as d-pad hotspots, which
//! raygui — polling the raw mouse internally — cannot do.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const input = @import("../input.zig");

pub const ButtonOpts = struct {
    enabled: bool = true,
    textColor: ?rl.Color = null,
    fontSize: i32 = 19,
};

/// Yellow action button matching the old raygui style. True when clicked.
pub fn button(rect: rl.Rectangle, label: [:0]const u8) bool {
    return buttonEx(rect, label, .{});
}

pub fn buttonEx(rect: rl.Rectangle, label: [:0]const u8, opts: ButtonOpts) bool {
    const C = theme.CatppuccinMocha.Color;
    if (opts.enabled) input.registerHotspot(rect);

    const hovered = opts.enabled and rl.checkCollisionPointRec(input.pointerPos(), rect);
    const pressed = hovered and input.confirmDown();

    const bg = if (!opts.enabled) C.surface0 else if (hovered) C.peach else C.yellow;
    const borderColor = if (!opts.enabled) C.surface0 else if (hovered) C.surface2 else C.surface1;
    const labelColor = if (!opts.enabled) C.subtext0 else opts.textColor orelse C.base;

    const off: f32 = if (pressed) 1 else 0;
    const r = rl.Rectangle.init(rect.x + off, rect.y + off, rect.width, rect.height);
    rl.drawRectangleRec(r, bg);
    rl.drawRectangleLinesEx(r, 1, borderColor);

    const tw = text.measure(label, opts.fontSize);
    const tx = @as(i32, @intFromFloat(r.x + r.width / 2)) - @divFloor(tw, 2);
    const ty = @as(i32, @intFromFloat(r.y + (r.height - @as(f32, @floatFromInt(opts.fontSize))) / 2));
    text.draw(label, tx, ty, opts.fontSize, labelColor);

    return hovered and opts.enabled and input.confirmPressed();
}

// The slider being dragged, so the handle follows the pointer even when it
// slips off the track vertically mid-drag. Identified by its value pointer.
var activeSlider: ?*f32 = null;

/// Horizontal slider: track + yellow fill + round handle, value label on the
/// right. Updates `value` in place; true when it changed this frame.
pub fn slider(rect: rl.Rectangle, rightLabel: ?[:0]const u8, value: *f32, min: f32, max: f32) bool {
    const C = theme.CatppuccinMocha.Color;
    input.registerHotspot(rect);

    const mouse = input.pointerPos();
    // Generous grab area so the small handle isn't fiddly.
    const grabRect = rl.Rectangle.init(rect.x - 6, rect.y - 6, rect.width + 12, rect.height + 12);
    const hovered = rl.checkCollisionPointRec(mouse, grabRect);

    if (activeSlider == value and !input.confirmDown()) activeSlider = null;
    if (hovered and input.confirmPressed()) activeSlider = value;
    const dragging = activeSlider == value;

    const old = value.*;
    if (dragging) {
        const frac = std.math.clamp((mouse.x - rect.x) / rect.width, 0, 1);
        value.* = min + frac * (max - min);
    }

    // Track, fill, handle
    const midY = rect.y + rect.height / 2;
    const trackH: f32 = 8;
    const track = rl.Rectangle.init(rect.x, midY - trackH / 2, rect.width, trackH);
    rl.drawRectangleRounded(track, 1.0, 4, C.surface1);
    const frac = std.math.clamp((value.* - min) / (max - min), 0, 1);
    if (frac > 0) {
        rl.drawRectangleRounded(rl.Rectangle.init(track.x, track.y, track.width * frac, trackH), 1.0, 4, C.yellow);
    }
    const hx = rect.x + rect.width * frac;
    const hr: f32 = if (hovered or dragging) 9 else 8;
    rl.drawCircleV(rl.Vector2.init(hx, midY), hr, if (dragging) C.peach else C.yellow);
    rl.drawCircleLinesV(rl.Vector2.init(hx, midY), hr, C.surface2);

    if (rightLabel) |label| {
        text.draw(label, @intFromFloat(rect.x + rect.width + 12), @intFromFloat(midY - 9), 17, C.text);
    }

    return @abs(value.* - old) > 0.0001;
}
