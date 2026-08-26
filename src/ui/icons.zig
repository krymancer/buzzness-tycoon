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

/// Royal crown: a band with three spikes and a gem on each tip, centered on
/// (cx, cy) with width `w` (height is about 0.8 * w). Prestige motif.
pub fn drawCrown(cx: f32, cy: f32, w: f32, color: rl.Color, gem: rl.Color) void {
    const h = w * 0.8;
    const left = cx - w / 2;
    const right = cx + w / 2;
    const bandTop = cy + h * 0.15;
    const bottom = cy + h / 2;
    const tipY = cy - h / 2;
    const midTipY = cy - h * 0.6;
    // Band.
    rl.drawRectangleRec(rl.Rectangle.init(left, bandTop, w, bottom - bandTop), color);
    // Three spikes (both windings so culling can't hide one).
    const spikes = [3][3]rl.Vector2{
        .{ rl.Vector2.init(left, bandTop + 1), rl.Vector2.init(left, tipY), rl.Vector2.init(cx - w * 0.16, bandTop + 1) },
        .{ rl.Vector2.init(cx - w * 0.28, bandTop + 1), rl.Vector2.init(cx, midTipY), rl.Vector2.init(cx + w * 0.28, bandTop + 1) },
        .{ rl.Vector2.init(cx + w * 0.16, bandTop + 1), rl.Vector2.init(right, tipY), rl.Vector2.init(right, bandTop + 1) },
    };
    for (spikes) |p| {
        rl.drawTriangle(p[0], p[1], p[2], color);
        rl.drawTriangle(p[2], p[1], p[0], color);
    }
    const gemR = @max(1.5, w * 0.09);
    rl.drawCircleV(rl.Vector2.init(left + gemR * 0.4, tipY), gemR, gem);
    rl.drawCircleV(rl.Vector2.init(cx, midTipY), gemR * 1.2, gem);
    rl.drawCircleV(rl.Vector2.init(right - gemR * 0.4, tipY), gemR, gem);
}

/// Same drop ringed with a dark outline, to match text.drawOutline glyphs.
pub fn drawHoneyDropOutlined(cx: f32, cy: f32, r: f32, color: rl.Color, outline: rl.Color) void {
    drawHoneyDrop(cx, cy, r + 2, outline);
    drawHoneyDrop(cx, cy, r, color);
}

pub const ArrowDir = enum { up, down, left, right };

/// Solid triangular arrow centered on (cx, cy), half-extent `r`. Used for
/// d-pad hint chips (the UI font has no arrow glyphs). Drawn in both
/// windings so backface culling can never hide it.
pub fn drawArrow(cx: f32, cy: f32, r: f32, dir: ArrowDir, color: rl.Color) void {
    const p: [3]rl.Vector2 = switch (dir) {
        .up => .{ rl.Vector2.init(cx, cy - r), rl.Vector2.init(cx - r, cy + r * 0.7), rl.Vector2.init(cx + r, cy + r * 0.7) },
        .down => .{ rl.Vector2.init(cx, cy + r), rl.Vector2.init(cx - r, cy - r * 0.7), rl.Vector2.init(cx + r, cy - r * 0.7) },
        .left => .{ rl.Vector2.init(cx - r, cy), rl.Vector2.init(cx + r * 0.7, cy - r), rl.Vector2.init(cx + r * 0.7, cy + r) },
        .right => .{ rl.Vector2.init(cx + r, cy), rl.Vector2.init(cx - r * 0.7, cy - r), rl.Vector2.init(cx - r * 0.7, cy + r) },
    };
    rl.drawTriangle(p[0], p[1], p[2], color);
    rl.drawTriangle(p[2], p[1], p[0], color);
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
