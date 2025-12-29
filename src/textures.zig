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
    pub fn init() !@This() {
        return .{
            .rose = try assets.loadTextureFromMemory(assets.rose_png),
            .tulip = try assets.loadTextureFromMemory(assets.tulip_png),
            .dandelion = try assets.loadTextureFromMemory(assets.dandelion_png),
            .bee = try assets.loadTextureFromMemory(assets.bee_png),
            .beehive = try assets.loadTextureFromMemory(assets.beehive_png),
        };
    }

    pub fn deinit(self: @This()) void {
        rl.unloadTexture(self.rose);
        rl.unloadTexture(self.dandelion);
        rl.unloadTexture(self.tulip);
        rl.unloadTexture(self.bee);
        rl.unloadTexture(self.beehive);
    }

    pub fn getFlowerTexture(self: @This(), flower: Flowers) rl.Texture {
        return switch (flower) {
            .rose => self.rose,
            .tulip => self.tulip,
            .dandelion => self.dandelion,
        };
    }
};
