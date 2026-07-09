const rl = @import("raylib");
const std = @import("std");

/// Cozy animated sky + day/night cycle.
///
/// Everything is driven off `rl.getTime()` so it needs no per-frame state
/// threading — the whole atmosphere is a pure function of the wall clock.
/// A full day/night cycle takes DAY_LENGTH seconds. Kept long and gentle so
/// the game reads as calm and AFK-friendly rather than a strobing disco.
pub const Sky = struct {
    pub const DAY_LENGTH: f32 = 300.0; // seconds for a full dawn→night→dawn loop
    const STAR_COUNT = 140;
    const CLOUD_COUNT = 7;

    // Start the world a little after sunrise so the first thing the player
    // sees is a bright, welcoming morning.
    const START_PHASE: f32 = 0.30;

    const Star = struct { x: f32, y: f32, size: f32, phase: f32 };
    const Cloud = struct { x: f32, y: f32, scale: f32, speed: f32, alpha: f32 };

    stars: [STAR_COUNT]Star,
    clouds: [CLOUD_COUNT]Cloud,

    // Deterministic little RNG so the sky layout is stable and doesn't disturb
    // raylib's global RNG (which the gameplay relies on).
    fn lcg(state: *u32) f32 {
        state.* = state.* *% 1664525 +% 1013904223;
        return @as(f32, @floatFromInt(state.* >> 8)) / @as(f32, @floatFromInt(1 << 24));
    }

    pub fn init() Sky {
        var s: Sky = undefined;
        var rng: u32 = 0x9e3779b9;

        for (&s.stars) |*star| {
            star.x = lcg(&rng);
            star.y = lcg(&rng) * 0.6; // upper 60% of the sky
            star.size = 0.6 + lcg(&rng) * 1.6;
            star.phase = lcg(&rng) * std.math.tau;
        }
        for (&s.clouds) |*cloud| {
            cloud.x = lcg(&rng);
            cloud.y = 0.05 + lcg(&rng) * 0.4;
            cloud.scale = 0.6 + lcg(&rng) * 1.1;
            cloud.speed = 0.004 + lcg(&rng) * 0.010;
            cloud.alpha = 0.35 + lcg(&rng) * 0.4;
        }
        return s;
    }

    /// Dev/screenshot hook: when set, freezes the clock at this phase.
    pub var phaseOverride: ?f32 = null;

    /// Normalized time of day in [0,1): 0 = midnight, 0.25 = sunrise,
    /// 0.5 = noon, 0.75 = sunset.
    pub fn timeOfDay(_: *const Sky) f32 {
        if (phaseOverride) |p| return @mod(p, 1.0);
        const t = @as(f32, @floatCast(rl.getTime()));
        return @mod(t / DAY_LENGTH + START_PHASE, 1.0);
    }

    /// Sun elevation in [-1,1]. >0 is above the horizon (daytime).
    pub fn sunElevation(self: *const Sky) f32 {
        return -@cos(self.timeOfDay() * std.math.tau);
    }

    /// 0 = full day, 1 = deep night. Smooth around the horizon crossings.
    pub fn nightFactor(self: *const Sky) f32 {
        return smoothstep(0.10, -0.20, self.sunElevation());
    }

    // ---- gradient keyframes -------------------------------------------------

    const Key = struct { pos: f32, top: [3]f32, hor: [3]f32 };
    const KEYS = [_]Key{
        .{ .pos = 0.00, .top = .{ 12, 12, 30 }, .hor = .{ 30, 26, 56 } }, // midnight
        .{ .pos = 0.20, .top = .{ 34, 30, 66 }, .hor = .{ 70, 50, 92 } }, // pre-dawn
        .{ .pos = 0.25, .top = .{ 78, 92, 146 }, .hor = .{ 244, 156, 112 } }, // sunrise
        .{ .pos = 0.33, .top = .{ 126, 168, 214 }, .hor = .{ 250, 214, 176 } }, // morning
        .{ .pos = 0.50, .top = .{ 120, 178, 228 }, .hor = .{ 206, 228, 236 } }, // noon
        .{ .pos = 0.67, .top = .{ 128, 158, 210 }, .hor = .{ 250, 208, 154 } }, // afternoon
        .{ .pos = 0.75, .top = .{ 96, 74, 138 }, .hor = .{ 246, 122, 92 } }, // sunset
        .{ .pos = 0.82, .top = .{ 48, 38, 84 }, .hor = .{ 122, 62, 96 } }, // dusk
        .{ .pos = 1.00, .top = .{ 12, 12, 30 }, .hor = .{ 30, 26, 56 } }, // midnight
    };

    fn sampleGradient(t: f32) struct { top: rl.Color, hor: rl.Color } {
        var i: usize = 0;
        while (i + 1 < KEYS.len and t > KEYS[i + 1].pos) : (i += 1) {}
        const a = KEYS[i];
        const b = KEYS[@min(i + 1, KEYS.len - 1)];
        const span = @max(0.0001, b.pos - a.pos);
        const f = std.math.clamp((t - a.pos) / span, 0.0, 1.0);
        return .{
            .top = lerpRGB(a.top, b.top, f),
            .hor = lerpRGB(a.hor, b.hor, f),
        };
    }

    // ---- drawing ------------------------------------------------------------

    /// Full-screen background: gradient sky, stars, celestial bodies, clouds.
    /// Call right after beginDrawing(), before the world.
    pub fn drawBackground(self: *const Sky, width: f32, height: f32) void {
        const t = self.timeOfDay();
        const grad = sampleGradient(t);
        const w: i32 = @intFromFloat(width);
        const h: i32 = @intFromFloat(height);

        // Two-band gradient: sky top → warm horizon, with a subtle darker
        // lower band so the floating island reads against it.
        const horizonY: f32 = height * 0.60;
        rl.drawRectangleGradientV(0, 0, w, @intFromFloat(horizonY), grad.top, grad.hor);
        const lower = rl.colorLerp(grad.hor, grad.top, 0.55);
        rl.drawRectangleGradientV(0, @intFromFloat(horizonY), w, h - @as(i32, @intFromFloat(horizonY)), grad.hor, lower);

        const night = self.nightFactor();
        const time = @as(f32, @floatCast(rl.getTime()));

        // Stars — fade in with night, gentle twinkle.
        if (night > 0.02) {
            for (self.stars) |star| {
                const tw = 0.55 + 0.45 * @sin(time * 1.8 + star.phase);
                const a = night * tw;
                if (a <= 0.02) continue;
                const col = rl.Color.init(240, 240, 255, @intFromFloat(std.math.clamp(a, 0, 1) * 235));
                rl.drawCircle(@intFromFloat(star.x * width), @intFromFloat(star.y * height), star.size, col);
            }
        }

        self.drawSun(width, height, horizonY);
        self.drawClouds(width, night, time);
    }

    /// Sun/moon, drawn as a foreground pass (after the ambient light wash) so
    /// Sun, drawn in the background pass so it rises/sets *behind* the floating
    /// island. Daytime has no night veil, so it stays bright without a
    /// foreground pass.
    fn drawSun(self: *const Sky, width: f32, height: f32, horizonY: f32) void {
        const t = self.timeOfDay();
        const e = self.sunElevation();
        const arc = height * 0.46;
        if (e <= -0.12) return;
        const dayX = std.math.clamp((t - 0.25) / 0.5, -0.15, 1.15);
        const sx = width * (0.12 + 0.76 * dayX);
        const sy = horizonY - e * arc;
        const glow = std.math.clamp(e + 0.3, 0.0, 1.0);
        rl.drawCircleGradient(rl.Vector2.init(sx, sy), 120, rl.Color.init(255, 226, 150, @intFromFloat(80 * glow)), rl.Color.init(255, 226, 150, 0));
        rl.drawCircle(@intFromFloat(sx), @intFromFloat(sy), 30, rl.Color.init(255, 244, 214, 255));
        rl.drawCircle(@intFromFloat(sx), @intFromFloat(sy), 23, rl.Color.init(255, 236, 170, 255));
    }

    /// they stay bright and crisp instead of being muted by the night veil.
    /// Foreground pass: just the moon (drawn after the ambient wash so it stays
    /// crisp at night). The sun lives in the background pass, see drawSun.
    pub fn drawCelestial(self: *const Sky, width: f32, height: f32) void {
        const horizonY: f32 = height * 0.60;
        const e = self.sunElevation();
        const t = self.timeOfDay();
        const arc = height * 0.46;

        // Moon: opposite the sun, a soft full moon with a wide gentle halo.
        const me = -e;
        if (me > -0.05) {
            const mt = @mod(t + 0.5, 1.0);
            const nightX = std.math.clamp((mt - 0.25) / 0.5, -0.15, 1.15);
            const mx = width * (0.12 + 0.76 * nightX);
            const my = horizonY - me * arc;
            const vis = std.math.clamp(me + 0.05, 0.0, 1.0);
            rl.drawCircleGradient(rl.Vector2.init(mx, my), 110, rl.Color.init(210, 222, 255, @intFromFloat(38 * vis)), rl.Color.init(210, 222, 255, 0));
            rl.drawCircle(@intFromFloat(mx), @intFromFloat(my), 30, rl.Color.init(226, 232, 255, @intFromFloat(70 * vis)));
            rl.drawCircle(@intFromFloat(mx), @intFromFloat(my), 24, rl.Color.init(240, 244, 255, @intFromFloat(255 * vis)));
            // A couple of faint craters for character.
            const crater = rl.Color.init(206, 214, 244, @intFromFloat(255 * vis));
            rl.drawCircle(@intFromFloat(mx - 8), @intFromFloat(my - 6), 4, crater);
            rl.drawCircle(@intFromFloat(mx + 7), @intFromFloat(my + 5), 5, crater);
            rl.drawCircle(@intFromFloat(mx + 2), @intFromFloat(my - 9), 3, crater);
        }
    }

    fn drawClouds(self: *const Sky, width: f32, night: f32, time: f32) void {
        // Clouds go grey-blue and dim at night.
        const bright: u8 = @intFromFloat(255 - night * 130);
        for (self.clouds) |cloud| {
            const drift = @mod(cloud.x + time * cloud.speed, 1.2) - 0.1;
            const cx = drift * width;
            const cy = cloud.y * width * 0.34;
            const s = cloud.scale;
            const a: u8 = @intFromFloat(cloud.alpha * (1.0 - night * 0.55) * 255);
            const col = rl.Color.init(bright, bright, @min(255, @as(u16, bright) + 8), a);
            // A puff = a few overlapping soft ellipses.
            rl.drawEllipse(@intFromFloat(cx), @intFromFloat(cy), 46 * s, 22 * s, col);
            rl.drawEllipse(@intFromFloat(cx - 34 * s), @intFromFloat(cy + 8 * s), 32 * s, 17 * s, col);
            rl.drawEllipse(@intFromFloat(cx + 36 * s), @intFromFloat(cy + 9 * s), 30 * s, 16 * s, col);
            rl.drawEllipse(@intFromFloat(cx + 6 * s), @intFromFloat(cy - 10 * s), 30 * s, 18 * s, col);
        }
    }

    /// Ambient lighting veil + vignette, drawn over the world (after sprites,
    /// before the HUD) so the whole meadow shares one light. Cheap: a couple
    /// of translucent full-screen passes.
    pub fn drawAmbientOverlay(self: *const Sky, width: f32, height: f32) void {
        const w: i32 = @intFromFloat(width);
        const h: i32 = @intFromFloat(height);
        const e = self.sunElevation();
        const night = self.nightFactor();

        // Cool night veil.
        if (night > 0.01) {
            rl.drawRectangle(0, 0, w, h, rl.Color.init(20, 24, 60, @intFromFloat(night * 120)));
        }
        // Warm twilight wash around sunrise/sunset (peaks when sun near horizon).
        const twilight = std.math.clamp(1.0 - @abs(e) * 4.0, 0.0, 1.0);
        if (twilight > 0.01) {
            rl.drawRectangle(0, 0, w, h, rl.Color.init(255, 150, 90, @intFromFloat(twilight * 42)));
        }
        // Gentle always-on vignette for cozy framing.
        const r = @max(width, height) * 0.75;
        rl.drawCircleGradient(rl.Vector2.init(width * 0.5, height * 0.5), r, rl.Color.init(0, 0, 0, 0), rl.Color.init(0, 0, 0, 70));
    }

    /// Tint applied to world sprites so bees/flowers pick up the ambient light.
    pub fn worldTint(self: *const Sky) rl.Color {
        const e = self.sunElevation();
        const night = self.nightFactor();
        // Warm daylight → dim cool moonlight, with a golden push near the horizon.
        const day = rl.Color.init(255, 250, 240, 255);
        const nightCol = rl.Color.init(150, 165, 210, 255);
        var tint = rl.colorLerp(day, nightCol, night * 0.85);
        const golden = std.math.clamp(1.0 - @abs(e) * 4.0, 0.0, 1.0) * 0.5;
        if (golden > 0.01) tint = rl.colorLerp(tint, rl.Color.init(255, 198, 150, 255), golden);
        return tint;
    }
};

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

fn lerpRGB(a: [3]f32, b: [3]f32, f: f32) rl.Color {
    return rl.Color.init(
        @intFromFloat(std.math.clamp(a[0] + (b[0] - a[0]) * f, 0, 255)),
        @intFromFloat(std.math.clamp(a[1] + (b[1] - a[1]) * f, 0, 255)),
        @intFromFloat(std.math.clamp(a[2] + (b[2] - a[2]) * f, 0, 255)),
        255,
    );
}
