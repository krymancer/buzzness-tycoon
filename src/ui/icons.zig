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

/// Sprout: a stem with two leaves, standing on (cx, baseY) with height `h`.
/// Icon for the Instant Grow ability.
pub fn drawSprout(cx: f32, baseY: f32, h: f32, color: rl.Color) void {
    const stemW = @max(2.0, h * 0.16);
    rl.drawLineEx(rl.Vector2.init(cx, baseY), rl.Vector2.init(cx, baseY - h), stemW, color);
    // Left leaf (lower) and right leaf (higher); draw each triangle in both
    // windings so backface culling can never hide one.
    const leafPts = [2][3]rl.Vector2{
        .{
            rl.Vector2.init(cx, baseY - h * 0.35),
            rl.Vector2.init(cx - h * 0.55, baseY - h * 0.6),
            rl.Vector2.init(cx - h * 0.12, baseY - h * 0.78),
        },
        .{
            rl.Vector2.init(cx, baseY - h * 0.6),
            rl.Vector2.init(cx + h * 0.55, baseY - h * 0.85),
            rl.Vector2.init(cx + h * 0.12, baseY - h * 1.0),
        },
    };
    for (leafPts) |p| {
        rl.drawTriangle(p[0], p[1], p[2], color);
        rl.drawTriangle(p[2], p[1], p[0], color);
    }
}

/// Same drop ringed with a dark outline, to match text.drawOutline glyphs.
pub fn drawHoneyDropOutlined(cx: f32, cy: f32, r: f32, color: rl.Color, outline: rl.Color) void {
    drawHoneyDrop(cx, cy, r + 2, outline);
    drawHoneyDrop(cx, cy, r, color);
}

/// Aura: a dot with two concentric rings, centered on (cx, cy), outer radius `r`.
/// Icon for the Lab: Aura passive.
pub fn drawAura(cx: f32, cy: f32, r: f32, color: rl.Color) void {
    rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy), r * 0.22, color);
    rl.drawRing(rl.Vector2.init(cx, cy), r * 0.5, r * 0.5 + @max(1.5, r * 0.14), 0, 360, 24, color);
    var faint = color;
    faint.a = @intFromFloat(@as(f32, @floatFromInt(color.a)) * 0.55);
    rl.drawRing(rl.Vector2.init(cx, cy), r - @max(1.5, r * 0.12), r, 0, 360, 28, faint);
}
