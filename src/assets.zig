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

pub fn loadImageFromMemory(fileData: []const u8) !rl.Image {
    return rl.loadImageFromMemory(".png", fileData);
}

pub fn loadTextureFromMemory(fileData: []const u8) !rl.Texture {
    const image = try loadImageFromMemory(fileData);
    defer rl.unloadImage(image);
    return rl.loadTextureFromImage(image);
}
