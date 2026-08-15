//! Shared UI font. Loads a rounded, legible TTF (Baloo 2) once and exposes
//! `draw`/`measure` helpers that are signature-compatible with rl.drawText /
//! rl.measureText, so the rest of the UI reads the same but renders in a much
//! more readable typeface than raylib's tiny pixel default. Also feeds the font
//! to raygui so buttons/menus match.

const rl = @import("raylib");
const rg = @import("raygui");
const assets = @import("assets.zig");

// Atlas is rasterized at a high base size and scaled down with bilinear
// filtering. Include Latin-1 so Portuguese accents render correctly.
const BASE_SIZE: i32 = 64;
const FONT_CHARS = blk: {
    var chars: [191]i32 = undefined;
    var index: usize = 0;
    for (32..127) |codepoint| {
        chars[index] = @intCast(codepoint);
        index += 1;
    }
    for (160..256) |codepoint| {
        chars[index] = @intCast(codepoint);
        index += 1;
    }
    break :blk chars;
};

var font: rl.Font = undefined;
var ready = false;

/// Create the font atlas. Must be called after the window/GL context exists.
pub fn load() void {
    font = rl.loadFontFromMemory(".ttf", assets.baloo2_ttf, BASE_SIZE, &FONT_CHARS) catch {
        ready = false;
        return;
    };
    rl.setTextureFilter(font.texture, .bilinear);
    ready = true;
}

/// Point raygui at our font. Called at the end of theme setup, because
/// raygui's loadStyleDefault() resets the font back to its built-in one.
pub fn applyToRaygui() void {
    if (!ready) return;
    rg.setFont(font);
}

pub fn unload() void {
    if (ready) rl.unloadFont(font);
}

fn spacing(size: i32) f32 {
    return @max(1.0, @as(f32, @floatFromInt(size)) * 0.06);
}

/// Drop-in for rl.drawText.
pub fn draw(txt: [:0]const u8, x: i32, y: i32, size: i32, color: rl.Color) void {
    if (!ready) {
        rl.drawText(txt, x, y, size, color);
        return;
    }
    rl.drawTextEx(font, txt, rl.Vector2.init(@floatFromInt(x), @floatFromInt(y)), @floatFromInt(size), spacing(size), color);
}

/// Drop-in for rl.measureText.
pub fn measure(txt: [:0]const u8, size: i32) i32 {
    if (!ready) return rl.measureText(txt, size);
    return @intFromFloat(rl.measureTextEx(font, txt, @floatFromInt(size), spacing(size)).x);
}

/// Like `draw`, but lays a soft dark drop-shadow behind the text first so it
/// stays legible over the bright, busy meadow. Shadow alpha tracks the text's
/// own alpha, so it fades correctly with animated (fading) labels.
pub fn drawShadow(txt: [:0]const u8, x: i32, y: i32, size: i32, color: rl.Color) void {
    const off: i32 = @max(1, @divTrunc(size, 14));
    const sa: u8 = @intFromFloat(@as(f32, @floatFromInt(color.a)) * 0.6);
    draw(txt, x + off, y + off, size, rl.Color.init(0, 0, 0, sa));
    draw(txt, x, y, size, color);
}
