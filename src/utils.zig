const std = @import("std");
const rl = @import("raylib");

pub fn isoToXY(i: f32, j: f32, width: f32, height: f32, offsetX: f32, offsetY: f32, scale: f32) rl.Vector2 {
    const halfScaledWidth: f32 = width * scale / 2.0;
    const quarterScaledHeight: f32 = height * scale / 4.0;

    const screenX: f32 = (i - j) * halfScaledWidth - halfScaledWidth + offsetX;
    const screenY: f32 = (i + j) * quarterScaledHeight + offsetY;

    return rl.Vector2.init(screenX, screenY);
}

/// Exact inverse of isoToXY, in cell coordinates: cell (i, j) covers
/// [i, i+1) x [j, j+1), so `floor()` of the result is the cell under the
/// point. Anchors: tile (0,0)'s diamond top vertex sits at (offsetX, offsetY)
/// and its center at (offsetX, offsetY + height*scale/4), which must map to
/// (0.5, 0.5). (A previous version shifted x by half a tile, mapping the
/// center to (1.0, 0.0) — so half of every diamond floored to a neighbor.)
pub fn xyToIso(x: f32, y: f32, width: f32, height: f32, offsetX: f32, offsetY: f32, scale: f32) rl.Vector2 {
    const half_scaled_width = width * scale / 2.0;
    const quarter_scaled_height = height * scale / 4.0;

    const u = (x - offsetX) / half_scaled_width;
    const v = (y - offsetY) / quarter_scaled_height;

    return rl.Vector2.init((u + v) / 2.0, (v - u) / 2.0);
}

pub fn isPointInIsometricTile(x: f32, y: f32, tileX: f32, tileY: f32, tileWidth: f32, tileHeight: f32, offsetX: f32, offsetY: f32, scale: f32) bool {
    const tileScreenPos = isoToXY(tileX, tileY, tileWidth, tileHeight, offsetX, offsetY, scale);

    const halfWidth = tileWidth * scale / 2.0;
    const halfHeight = tileHeight * scale / 2.0;

    const tileCenterX = tileScreenPos.x + halfWidth;
    const tileCenterY = tileScreenPos.y + halfHeight / 2.0;

    const relX = x - tileCenterX;
    const relY = y - tileCenterY;

    const normalizedX = @abs(relX) / halfWidth;
    const normalizedY = @abs(relY) / halfHeight;

    return normalizedX + normalizedY * 2.0 <= 1.0;
}

pub fn calculateCenteredGridOffset(gridWidth: usize, gridHeight: usize, tileWidth: f32, tileHeight: f32, scale: f32, viewportWidth: f32, viewportHeight: f32) rl.Vector2 {
    const topCorner = rl.Vector2.init(0, 0);
    const rightCorner = rl.Vector2.init(@floatFromInt(gridWidth - 1), 0);
    const bottomCorner = rl.Vector2.init(@floatFromInt(gridWidth - 1), @floatFromInt(gridHeight - 1));
    const leftCorner = rl.Vector2.init(0, @floatFromInt(gridHeight - 1));

    const topScreen = isoToXY(topCorner.x, topCorner.y, tileWidth, tileHeight, 0, 0, scale);
    const rightScreen = isoToXY(rightCorner.x, rightCorner.y, tileWidth, tileHeight, 0, 0, scale);
    const bottomScreen = isoToXY(bottomCorner.x, bottomCorner.y, tileWidth, tileHeight, 0, 0, scale);
    const leftScreen = isoToXY(leftCorner.x, leftCorner.y, tileWidth, tileHeight, 0, 0, scale);

    const minX = @min(@min(topScreen.x, rightScreen.x), @min(bottomScreen.x, leftScreen.x));
    const maxX = @max(@max(topScreen.x, rightScreen.x), @max(bottomScreen.x, leftScreen.x)) + tileWidth * scale;
    const minY = @min(@min(topScreen.y, rightScreen.y), @min(bottomScreen.y, leftScreen.y));
    const maxY = @max(@max(topScreen.y, rightScreen.y), @max(bottomScreen.y, leftScreen.y)) + tileHeight * scale;

    const gridScreenWidth = maxX - minX;
    const gridScreenHeight = maxY - minY;

    const offsetX = (viewportWidth - gridScreenWidth) / 2.0 - minX;
    const offsetY = (viewportHeight - gridScreenHeight) / 2.0 - minY;

    return rl.Vector2.init(offsetX, offsetY);
}

pub fn worldToGrid(worldPos: rl.Vector2, offset: rl.Vector2, scale: f32) rl.Vector2 {
    const tileWidth = 32.0;
    const tileHeight = 32.0;
    return xyToIso(worldPos.x, worldPos.y, tileWidth, tileHeight, offset.x, offset.y, scale);
}

test "xyToIso floors to the tile whose diamond contains the point" {
    const tw: f32 = 32;
    const th: f32 = 32;
    const offX: f32 = 137;
    const offY: f32 = 59;
    const scale: f32 = 2.5;

    const cells = [_][2]f32{ .{ 0, 0 }, .{ 3, 1 }, .{ 1, 4 }, .{ 8, 8 } };
    for (cells) |cell| {
        const i = cell[0];
        const j = cell[1];
        // Diamond center: sprite top-left + (tileW*scale/2, tileH*scale/4).
        const topLeft = isoToXY(i, j, tw, th, offX, offY, scale);
        const cx = topLeft.x + tw * scale / 2.0;
        const cy = topLeft.y + th * scale / 4.0;

        // The center and points near each diamond edge midpoint-to-center must
        // all resolve to this cell.
        const probes = [_][2]f32{
            .{ cx, cy },
            .{ cx + tw * scale / 2.0 * 0.9, cy },
            .{ cx - tw * scale / 2.0 * 0.9, cy },
            .{ cx, cy + th * scale / 4.0 * 0.9 },
            .{ cx, cy - th * scale / 4.0 * 0.9 },
        };
        for (probes) |p| {
            const iso = xyToIso(p[0], p[1], tw, th, offX, offY, scale);
            try std.testing.expectEqual(i, @floor(iso.x));
            try std.testing.expectEqual(j, @floor(iso.y));
        }
    }
}
