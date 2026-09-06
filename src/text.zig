//! Shared BoldPixels UI font by YukiPixels (CC BY-SA 4.0).
//! Uses a point-filtered atlas and matching draw/measure spacing.

const rl = @import("raylib");
const rg = @import("raygui");
const assets = @import("assets.zig");

// Rasterize at a multiple of the font’s 16px design size.
// Latin-1 includes Brazilian Portuguese accents.
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
    font = rl.loadFontFromMemory(".ttf", assets.boldpixels_ttf, BASE_SIZE, &FONT_CHARS) catch {
        ready = false;
        return;
    };
    rl.setTextureFilter(font.texture, .point);
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

fn spacing(_: i32) f32 {
    return 0;
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

/// Like `draw`, but rings the glyphs with a dark outline (8 offset passes) so
/// the text reads over any background without needing a backing panel.
pub fn drawOutline(txt: [:0]const u8, x: i32, y: i32, size: i32, color: rl.Color, outline: rl.Color) void {
    const o: i32 = @max(1, @divTrunc(size, 18));
    var oc = outline;
    // Outline alpha tracks the text's own alpha so fading labels fade whole.
    oc.a = @intFromFloat(@as(f32, @floatFromInt(outline.a)) * @as(f32, @floatFromInt(color.a)) / 255.0);
    const offsets = [_][2]i32{
        .{ -o, 0 },  .{ o, 0 },  .{ 0, -o }, .{ 0, o },
        .{ -o, -o }, .{ o, -o }, .{ -o, o }, .{ o, o },
    };
    for (offsets) |d| {
        draw(txt, x + d[0], y + d[1], size, oc);
    }
    draw(txt, x, y, size, color);
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
