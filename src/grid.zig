const rl = @import("raylib");
const std = @import("std");
const utils = @import("utils.zig");
const assets = @import("assets.zig");

pub const Grid = struct {
    width: usize,
    height: usize,

    tileTexture: rl.Texture,
    tileWidth: f32,
    tileHeight: f32,

    offset: rl.Vector2,

    scale: f32,
    baseScale: f32,
    minScale: f32,
    maxScale: f32,

    viewportWidth: f32,
    viewportHeight: f32,

    debug: bool,
    pub fn init(width: usize, height: usize, viewportWidth: f32, viewportHeight: f32) !@This() {
        const tileWidth = 32;
        const tileHeight = 32;
        const baseScale = 3;

        const offset = utils.calculateCenteredGridOffset(width, height, tileWidth, tileHeight, baseScale, viewportWidth, viewportHeight);

        return .{
            .width = width,
            .height = height,

            .offset = offset,

            .tileTexture = try assets.loadTextureFromMemory(assets.grass_cube_png),
            .tileWidth = tileWidth,
            .tileHeight = tileHeight,
            .scale = baseScale,
            .baseScale = baseScale,
            .minScale = 1.0,
            .maxScale = 6.0,

            .viewportWidth = viewportWidth,
            .viewportHeight = viewportHeight,

            .debug = true,
        };
    }

    pub fn zoom(self: *@This(), zoomDelta: f32) void {
        const newScale = self.scale + zoomDelta;
        self.scale = @max(self.minScale, @min(self.maxScale, newScale));
        self.updateOffset();
    }

    pub fn updateOffset(self: *@This()) void {
        self.offset = utils.calculateCenteredGridOffset(self.width, self.height, self.tileWidth, self.tileHeight, self.scale, self.viewportWidth, self.viewportHeight);
    }

    pub fn updateViewport(self: *@This(), viewportWidth: f32, viewportHeight: f32) void {
        self.viewportWidth = viewportWidth;
        self.viewportHeight = viewportHeight;
        self.updateOffset();
    }

    pub fn getRandomPositionInBounds(self: @This()) rl.Vector2 {
        const randomI = rl.getRandomValue(0, @as(i32, @intCast(self.width - 1)));
        const randomJ = rl.getRandomValue(0, @as(i32, @intCast(self.height - 1)));

        const worldPos = utils.isoToXY(@as(f32, @floatFromInt(randomI)), @as(f32, @floatFromInt(randomJ)), self.tileWidth, self.tileHeight, self.offset.x, self.offset.y, self.scale);

        const tileWidth = self.tileWidth * self.scale;
        const tileHeight = self.tileHeight * self.scale;

        const offsetX = @as(f32, @floatFromInt(rl.getRandomValue(0, @as(i32, @intFromFloat(tileWidth)))));
        const offsetY = @as(f32, @floatFromInt(rl.getRandomValue(0, @as(i32, @intFromFloat(tileHeight)))));

        return rl.Vector2.init(worldPos.x + offsetX, worldPos.y + offsetY);
    }

    pub fn deinit(self: @This()) void {
        rl.unloadTexture(self.tileTexture);
    }

    pub fn draw(self: @This(), tint: rl.Color) void {
        const screenWidth: f32 = @floatFromInt(rl.getScreenWidth());
        const screenHeight: f32 = @floatFromInt(rl.getScreenHeight());
        const margin: f32 = 64 * self.scale;

        const hovered = if (self.debug) self.getHoveredTile() else null;

        for (0..self.width) |i| {
            for (0..self.height) |j| {
                const x: f32 = @floatFromInt(i);
                const y: f32 = @floatFromInt(j);
                const position = utils.isoToXY(x, y, self.tileWidth, self.tileHeight, self.offset.x, self.offset.y, self.scale);

                if (position.x < -margin or position.x > screenWidth + margin or
                    position.y < -margin or position.y > screenHeight + margin)
                {
                    continue;
                }

                const isHovered = if (hovered) |h| (h.x == @as(i32, @intCast(i)) and h.y == @as(i32, @intCast(j))) else false;
                rl.drawTextureEx(self.tileTexture, position, 0, self.scale, rl.colorTint(rl.Color.white, tint));
                // Hover: a soft warm glow over the exact tile shape (a second
                // translucent pass), instead of harshly recolouring the cube.
                if (isHovered) {
                    rl.drawTextureEx(self.tileTexture, position, 0, self.scale, rl.Color.init(255, 236, 150, 120));
                }
            }
        }
    }

    pub fn isMouseHovering(self: @This(), x: f32, y: f32) bool {
        const mousePosition = rl.getMousePosition();
        return utils.isPointInIsometricTile(mousePosition.x, mousePosition.y, x, y, self.tileWidth, self.tileHeight, self.offset.x, self.offset.y, self.scale);
    }

    /// Returns the grid coordinates of the tile the mouse is currently hovering over, or null if off-grid.
    /// Uses the inverse isometric transform — O(1) regardless of grid size.
    ///
    /// `floor(xyToIso(mouse))` already maps every screen point to exactly one
    /// tile cell (the diamonds tile the plane with no gaps), so it's both the
    /// necessary and sufficient test. A previous extra "is-inside-diamond"
    /// re-check used a diamond centred differently from the cell, which rejected
    /// valid points near tile edges and produced dead zones where hover/click
    /// silently failed.
    pub fn getHoveredTile(self: @This()) ?struct { x: i32, y: i32 } {
        const mouse = rl.getMousePosition();
        const iso = utils.xyToIso(mouse.x, mouse.y, self.tileWidth, self.tileHeight, self.offset.x, self.offset.y, self.scale);
        const gi: i32 = @intFromFloat(@floor(iso.x));
        const gj: i32 = @intFromFloat(@floor(iso.y));
        if (gi < 0 or gj < 0 or gi >= @as(i32, @intCast(self.width)) or gj >= @as(i32, @intCast(self.height))) return null;
        return .{ .x = gi, .y = gj };
    }
};
