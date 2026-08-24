//! Textured input-prompt icons (16x16 pixel art): gamepad buttons, d-pad
//! directions, and keyboard keys. Textures load lazily on first draw (needs
//! the GL context) and draw with point filtering so the pixels stay crisp at
//! any UI scale.

const rl = @import("raylib");
const assets = @import("../assets.zig");

pub const Icon = enum {
    pad_a,
    pad_b,
    pad_x,
    pad_y,
    pad_lb,
    pad_rb,
    pad_lt,
    pad_rt,
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
    key_1,
    key_2,
    key_3,
    key_4,
    key_t,
};

const COUNT = @typeInfo(Icon).@"enum".fields.len;
var textures: [COUNT]?rl.Texture = @splat(null);

fn data(icon: Icon) []const u8 {
    return switch (icon) {
        .pad_a => assets.ui_pad_a_png,
        .pad_b => assets.ui_pad_b_png,
        .pad_x => assets.ui_pad_x_png,
        .pad_y => assets.ui_pad_y_png,
        .pad_lb => assets.ui_pad_lb_png,
        .pad_rb => assets.ui_pad_rb_png,
        .pad_lt => assets.ui_pad_lt_png,
        .pad_rt => assets.ui_pad_rt_png,
        .dpad_up => assets.ui_dpad_up_png,
        .dpad_down => assets.ui_dpad_down_png,
        .dpad_left => assets.ui_dpad_left_png,
        .dpad_right => assets.ui_dpad_right_png,
        .key_1 => assets.ui_key_1_png,
        .key_2 => assets.ui_key_2_png,
        .key_3 => assets.ui_key_3_png,
        .key_4 => assets.ui_key_4_png,
        .key_t => assets.ui_key_t_png,
    };
}

/// Recolor the icon's glyph (the enclosed black pixels — a digit, letter, or
/// button symbol) to white for legibility on the dark UI, leaving the black
/// outer outline untouched. The two share the same black, so they're told
/// apart structurally: a flood fill from the sprite border through
/// transparent-or-black pixels reaches the outline but never the glyph,
/// which is sealed inside the gray key cap.
fn glyphToWhite(img: *rl.Image) void {
    const w: usize = @intCast(img.width);
    const h: usize = @intCast(img.height);
    if (w * h > 1024) return;
    const colors = rl.loadImageColors(img.*) catch return;
    defer rl.unloadImageColors(colors);

    const isPassable = struct {
        fn f(c: rl.Color) bool {
            return c.a == 0 or (c.r == 0 and c.g == 0 and c.b == 0);
        }
    }.f;

    var reached: [1024]bool = @splat(false);
    var stack: [1024]usize = undefined;
    var sp: usize = 0;
    for (0..h) |y| {
        for (0..w) |x| {
            if (x != 0 and y != 0 and x != w - 1 and y != h - 1) continue;
            const idx = y * w + x;
            if (isPassable(colors[idx]) and !reached[idx]) {
                reached[idx] = true;
                stack[sp] = idx;
                sp += 1;
            }
        }
    }
    while (sp > 0) {
        sp -= 1;
        const idx = stack[sp];
        const x = idx % w;
        const y = idx / w;
        const neighbors = [_]?usize{
            if (x > 0) idx - 1 else null,
            if (x + 1 < w) idx + 1 else null,
            if (y > 0) idx - w else null,
            if (y + 1 < h) idx + w else null,
        };
        for (neighbors) |n| {
            const ni = n orelse continue;
            if (!reached[ni] and isPassable(colors[ni])) {
                reached[ni] = true;
                stack[sp] = ni;
                sp += 1;
            }
        }
    }
    for (colors, 0..) |c, idx| {
        if (c.a == 255 and c.r == 0 and c.g == 0 and c.b == 0 and !reached[idx]) {
            rl.imageDrawPixel(img, @intCast(idx % w), @intCast(idx / w), rl.Color.white);
        }
    }
}

/// Draw `icon` with its top-left at (x, y), scaled to `size` px square.
/// Multiples of 16 stay pixel-perfect.
pub fn draw(icon: Icon, x: f32, y: f32, size: f32) void {
    const i = @intFromEnum(icon);
    if (textures[i] == null) {
        var img = assets.loadImageFromMemory(data(icon)) catch return;
        defer rl.unloadImage(img);
        glyphToWhite(&img);
        textures[i] = rl.loadTextureFromImage(img) catch return;
    }
    const tex = textures[i].?;
    rl.drawTexturePro(
        tex,
        rl.Rectangle.init(0, 0, @floatFromInt(tex.width), @floatFromInt(tex.height)),
        rl.Rectangle.init(x, y, size, size),
        rl.Vector2.init(0, 0),
        0,
        rl.Color.white,
    );
}

/// The number-key icon for a quick-buy slot index (0..3).
pub fn numberKey(index: usize) Icon {
    return switch (index) {
        0 => .key_1,
        1 => .key_2,
        2 => .key_3,
        else => .key_4,
    };
}

pub fn deinit() void {
    for (&textures) |*t| {
        if (t.*) |tex| rl.unloadTexture(tex);
        t.* = null;
    }
}
