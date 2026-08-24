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

/// Draw `icon` with its top-left at (x, y), scaled to `size` px square.
/// Multiples of 16 stay pixel-perfect.
pub fn draw(icon: Icon, x: f32, y: f32, size: f32) void {
    const i = @intFromEnum(icon);
    if (textures[i] == null) {
        textures[i] = assets.loadTextureFromMemory(data(icon)) catch return;
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
