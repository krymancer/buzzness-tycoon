const std = @import("std");
const rl = @import("raylib");
const sprites = @import("sprites");

pub const bee_png = sprites.bee_png;
pub const rose_png = sprites.rose_png;
pub const dandelion_png = sprites.dandelion_png;
pub const tulip_png = sprites.tulip_png;
pub const grass_cube_png = sprites.grass_cube_png;
pub const beehive_png = sprites.beehive_png;
pub const baloo2_ttf = sprites.baloo2_ttf;

pub const ui_cursor_png = sprites.ui_cursor_png;
pub const ui_pad_a_png = sprites.ui_pad_a_png;
pub const ui_pad_b_png = sprites.ui_pad_b_png;
pub const ui_pad_x_png = sprites.ui_pad_x_png;
pub const ui_pad_y_png = sprites.ui_pad_y_png;
pub const ui_pad_lb_png = sprites.ui_pad_lb_png;
pub const ui_pad_rb_png = sprites.ui_pad_rb_png;
pub const ui_pad_lt_png = sprites.ui_pad_lt_png;
pub const ui_pad_rt_png = sprites.ui_pad_rt_png;
pub const ui_dpad_up_png = sprites.ui_dpad_up_png;
pub const ui_dpad_down_png = sprites.ui_dpad_down_png;
pub const ui_dpad_left_png = sprites.ui_dpad_left_png;
pub const ui_dpad_right_png = sprites.ui_dpad_right_png;
pub const ui_key_1_png = sprites.ui_key_1_png;
pub const ui_key_2_png = sprites.ui_key_2_png;
pub const ui_key_3_png = sprites.ui_key_3_png;
pub const ui_key_4_png = sprites.ui_key_4_png;
pub const ui_key_t_png = sprites.ui_key_t_png;
pub const ui_key_tab_png = sprites.ui_key_tab_png;

pub fn loadImageFromMemory(fileData: []const u8) !rl.Image {
    return rl.loadImageFromMemory(".png", fileData);
}

pub fn loadTextureFromMemory(fileData: []const u8) !rl.Texture {
    const image = try loadImageFromMemory(fileData);
    defer rl.unloadImage(image);
    return rl.loadTextureFromImage(image);
}

pub const pink_tulip_png = sprites.pink_tulip_png;
pub const poppy_png = sprites.poppy_png;
pub const hyacinth_png = sprites.hyacinth_png;
pub const red_tulip_png = sprites.red_tulip_png;
pub const iris_png = sprites.iris_png;
