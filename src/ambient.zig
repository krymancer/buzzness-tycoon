const rl = @import("raylib");
const std = @import("std");
const clock = @import("clock.zig");

/// Screen-space ambient motes: drifting pollen dust by day that warms into
/// glowing, blinking fireflies at night. Purely decorative — floats in the
/// "air" over the meadow and never touches gameplay. Confined to the play area
/// (left of the side panel).
pub const Ambient = struct {
    const COUNT = 90;

    const Mote = struct {
        x: f32,
        y: f32,
        vx: f32,
        vy: f32,
        size: f32,
        phase: f32,
        blinkRate: f32,
    };

    motes: [COUNT]Mote,
    seeded: bool = false,

    fn lcg(state: *u32) f32 {
        state.* = state.* *% 1664525 +% 1013904223;
        return @as(f32, @floatFromInt(state.* >> 8)) / @as(f32, @floatFromInt(1 << 24));
    }

    pub fn init() Ambient {
        return .{ .motes = undefined, .seeded = false };
    }

    fn seed(self: *Ambient, w: f32, h: f32) void {
        var rng: u32 = 0x1234abcd;
        for (&self.motes) |*m| {
            m.x = lcg(&rng) * w;
            m.y = lcg(&rng) * h;
            m.vx = (lcg(&rng) - 0.5) * 14.0;
            m.vy = -(6.0 + lcg(&rng) * 12.0); // drift gently upward
            m.size = 1.0 + lcg(&rng) * 2.0;
            m.phase = lcg(&rng) * std.math.tau;
            m.blinkRate = 0.8 + lcg(&rng) * 1.6;
        }
        self.seeded = true;
    }

    pub fn update(self: *Ambient, dt: f32, playW: f32, playH: f32) void {
        if (!self.seeded) self.seed(playW, playH);
        const time = @as(f32, @floatCast(clock.time()));
        for (&self.motes) |*m| {
            // Lazy sine sway on top of the base drift so paths look organic.
            m.x += (m.vx + @sin(time * 0.6 + m.phase) * 6.0) * dt;
            m.y += m.vy * dt;
            // Wrap around the play area.
            if (m.y < -8) {
                m.y = playH + 8;
                m.x = @mod(m.x + 137.0, playW);
            }
            if (m.x < -8) m.x = playW + 8;
            if (m.x > playW + 8) m.x = -8;
        }
    }

    /// nightFactor in [0,1] blends pollen-dust → firefly behaviour.
    pub fn draw(self: *const Ambient, nightFactor: f32) void {
        const time = @as(f32, @floatCast(clock.time()));
        // Day: pale warm pollen. Night: glowing amber fireflies.
        const day = rl.Color.init(255, 244, 200, 255);
        const nite = rl.Color.init(190, 255, 150, 255);
        const col = rl.colorLerp(day, nite, nightFactor);

        for (self.motes) |m| {
            // Fireflies blink slowly and strongly; daytime dust barely shimmers.
            const blink = 0.5 + 0.5 * @sin(time * m.blinkRate + m.phase);
            const dayAlpha = 0.12 + 0.10 * blink;
            const niteAlpha = blink * blink * 0.9;
            const a = std.math.clamp(dayAlpha * (1.0 - nightFactor) + niteAlpha * nightFactor, 0.0, 1.0);
            if (a <= 0.02) continue;

            const r = m.size * (1.0 + nightFactor * 0.6);
            // Soft glow halo (stronger at night), plus a bright core.
            if (nightFactor > 0.1) {
                rl.drawCircleGradient(rl.Vector2.init(m.x, m.y), r * 4.0, rl.colorAlpha(col, a * 0.35 * nightFactor), rl.colorAlpha(col, 0));
            }
            rl.drawCircleV(rl.Vector2.init(m.x, m.y), r, rl.colorAlpha(col, a));
        }
    }
};
