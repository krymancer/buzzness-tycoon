const rl = @import("raylib");
const std = @import("std");

const assets = @import("assets.zig");

const components = @import("ecs/components.zig");

pub const Flowers = enum { rose, tulip, dandelion };

pub fn flowersToFlowerType(flower: Flowers) components.FlowerType {
    return switch (flower) {
        .rose => .rose,
        .tulip => .tulip,
        .dandelion => .dandelion,
    };
}

pub const Textures = struct {
    bee: rl.Texture,
    rose: rl.Texture,
    dandelion: rl.Texture,
    tulip: rl.Texture,
    beehive: rl.Texture,
    /// Grayscale copies of the flower sheets for rotten flowers. Baked once
    /// at load so withered flowers draw as plain textured quads: the old
    /// per-flower grayscale shader forced a render-batch flush for every
    /// rotten flower on screen.
    roseGray: rl.Texture,
    dandelionGray: rl.Texture,
    tulipGray: rl.Texture,

    pub fn init() !@This() {
        return .{
            .rose = try assets.loadTextureFromMemory(assets.rose_png),
            .tulip = try assets.loadTextureFromMemory(assets.tulip_png),
            .dandelion = try assets.loadTextureFromMemory(assets.dandelion_png),
            .bee = try assets.loadTextureFromMemory(assets.bee_png),
            .beehive = try assets.loadTextureFromMemory(assets.beehive_png),
            .roseGray = try loadGrayscale(assets.rose_png),
            .tulipGray = try loadGrayscale(assets.tulip_png),
            .dandelionGray = try loadGrayscale(assets.dandelion_png),
        };
    }

    fn loadGrayscale(fileData: []const u8) !rl.Texture {
        var image = try assets.loadImageFromMemory(fileData);
        defer rl.unloadImage(image);
        rl.imageColorGrayscale(&image);
        return rl.loadTextureFromImage(image);
    }

    pub fn deinit(self: @This()) void {
        rl.unloadTexture(self.rose);
        rl.unloadTexture(self.dandelion);
        rl.unloadTexture(self.tulip);
        rl.unloadTexture(self.bee);
        rl.unloadTexture(self.beehive);
        rl.unloadTexture(self.roseGray);
        rl.unloadTexture(self.dandelionGray);
        rl.unloadTexture(self.tulipGray);
    }

    /// Withered look-up for a flower type (same sheet layout as the colour one).
    pub fn grayFor(self: @This(), flower: components.FlowerType) rl.Texture {
        return switch (flower) {
            .rose => self.roseGray,
            .tulip => self.tulipGray,
            .dandelion => self.dandelionGray,
        };
    }

    pub fn getFlowerTexture(self: @This(), flower: Flowers) rl.Texture {
        return switch (flower) {
            .rose => self.rose,
            .tulip => self.tulip,
            .dandelion => self.dandelion,
        };
    }
};
