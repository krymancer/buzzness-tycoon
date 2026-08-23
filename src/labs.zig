const std = @import("std");

/// Aura honey bonus per tree level: x1.25 at Lv1, x1.50 at Lv2, ...
pub const AURA_PER_LEVEL: f32 = 0.25;

pub fn auraMultiplierForLevel(level: u16) f32 {
    return 1.0 + AURA_PER_LEVEL * @as(f32, @floatFromInt(level));
}

/// Aura radius in grid tiles: base reach once Aura is owned, +1 tile per
/// "Aura Reach" level. A circle in grid space is exactly the isometric
/// ellipse drawn on the meadow.
pub const AURA_BASE_REACH: f32 = 4.0;
pub const AURA_REACH_PER_LEVEL: f32 = 1.0;

pub fn auraReachForLevel(reachLevel: u16) f32 {
    return AURA_BASE_REACH + AURA_REACH_PER_LEVEL * @as(f32, @floatFromInt(reachLevel));
}

/// True when grid cell (gx, gy) lies within the aura centred on (hx, hy).
pub fn isInAura(gx: f32, gy: f32, hx: f32, hy: f32, reach: f32) bool {
    const dx = gx - hx;
    const dy = gy - hy;
    return dx * dx + dy * dy <= reach * reach;
}

pub const LabState = struct {
    /// Honey multiplier for pollen collected inside the aura (1 = no Aura).
    auraMul: f32 = 1.0,
    /// Aura radius in grid tiles (0 = no Aura).
    auraReach: f32 = 0,

    /// Pollen multiplier for a flower at grid (gx, gy), hive at (hx, hy).
    pub fn pollenMultiplierAt(self: *const @This(), gx: f32, gy: f32, hx: f32, hy: f32) f32 {
        if (self.auraReach <= 0) return 1.0;
        return if (isInAura(gx, gy, hx, hy, self.auraReach)) self.auraMul else 1.0;
    }
};

test "aura applies only inside its reach" {
    var l = LabState{ .auraMul = 1.5, .auraReach = 4 };
    try std.testing.expectEqual(@as(f32, 1.5), l.pollenMultiplierAt(8, 8, 8, 8));
    try std.testing.expectEqual(@as(f32, 1.5), l.pollenMultiplierAt(11, 8, 8, 8)); // d=3
    try std.testing.expectEqual(@as(f32, 1.0), l.pollenMultiplierAt(11, 11, 8, 8)); // d=4.24
    l.auraReach = 0;
    try std.testing.expectEqual(@as(f32, 1.0), l.pollenMultiplierAt(8, 8, 8, 8));
    try std.testing.expectEqual(@as(f32, 5), auraReachForLevel(1));
    try std.testing.expectEqual(@as(f32, 1.75), auraMultiplierForLevel(3));
}
