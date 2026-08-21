//! Tiny primitive-drawn icons shared across UI modules.

const rl = @import("raylib");

/// Honey drop: a round bead with a pointed top, centered on (cx, cy) with
/// bead radius `r`. Total height is about 2.8 * r, and the shape's optical
/// center sits at roughly (cx, cy - 0.65 * r).
pub fn drawHoneyDrop(cx: f32, cy: f32, r: f32, color: rl.Color) void {
    rl.drawTriangle(
        rl.Vector2.init(cx, cy - r - r * 0.8),
        rl.Vector2.init(cx - r * 0.72, cy - r * 0.5),
        rl.Vector2.init(cx + r * 0.72, cy - r * 0.5),
        color,
    );
    rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy), r, color);
}

/// Same drop ringed with a dark outline, to match text.drawOutline glyphs.
pub fn drawHoneyDropOutlined(cx: f32, cy: f32, r: f32, color: rl.Color, outline: rl.Color) void {
    drawHoneyDrop(cx, cy, r + 2, outline);
    drawHoneyDrop(cx, cy, r, color);
}
