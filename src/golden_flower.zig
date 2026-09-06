//! The golden flower: now and then a glowing bloom appears on a random tile
//! for a few seconds. Clicking it pays a lump of honey (a minute of income).
//! It only happens while the game is on screen — the presence reward the
//! design leans on — and it's the one thing on the meadow that asks for a
//! quick reaction.

const std = @import("std");
const rl = @import("raylib");

pub const LIFETIME: f32 = 12.0;
/// Seconds between appearances (uniform in this range).
pub const SPAWN_MIN: f32 = 100.0;
pub const SPAWN_MAX: f32 = 200.0;
/// Reward: this many seconds of the current honey/sec, at least the floor.
pub const REWARD_SECONDS: f32 = 60.0;
pub const REWARD_MIN: f32 = 100.0;

pub var active: bool = false;
pub var x: i32 = 0;
pub var y: i32 = 0;
pub var lifeLeft: f32 = 0;
var nextIn: f32 = 0;
/// Dev: BT_GOLDEN=1 makes the first one appear right away.
pub var devSpawnNow: bool = false;

pub fn reset() void {
    active = false;
    nextIn = randomWait();
}

fn randomWait() f32 {
    return SPAWN_MIN + (SPAWN_MAX - SPAWN_MIN) * @as(f32, @floatFromInt(rl.getRandomValue(0, 1000))) / 1000.0;
}

/// Tick. Returns true when the flower just vanished unclicked (so callers
/// can stay quiet) — the spawn position avoids the hive tile.
pub fn update(dt: f32, gridW: usize, gridH: usize) void {
    if (active) {
        lifeLeft -= dt;
        if (lifeLeft <= 0) {
            active = false;
            nextIn = randomWait();
        }
        return;
    }
    if (devSpawnNow) {
        devSpawnNow = false;
        nextIn = 0;
    }
    nextIn -= dt;
    if (nextIn > 0 or gridW < 3 or gridH < 3) return;
    const hx: i32 = @intCast((gridW - 1) / 2);
    const hy: i32 = @intCast((gridH - 1) / 2);
    var tries: usize = 0;
    while (tries < 8) : (tries += 1) {
        const px = rl.getRandomValue(0, @intCast(gridW - 1));
        const py = rl.getRandomValue(0, @intCast(gridH - 1));
        if (px == hx and py == hy) continue;
        x = px;
        y = py;
        active = true;
        lifeLeft = LIFETIME;
        return;
    }
    nextIn = randomWait();
}

/// Claim the flower if it's on (tx, ty). Returns the honey it pays.
pub fn tryClaim(tx: i32, ty: i32, honeyPerSec: f32) ?f32 {
    if (!active or tx != x or ty != y) return null;
    active = false;
    nextIn = randomWait();
    return reward(honeyPerSec);
}

pub fn reward(honeyPerSec: f32) f32 {
    if (!std.math.isFinite(honeyPerSec)) return REWARD_MIN;
    return @max(REWARD_MIN, honeyPerSec * REWARD_SECONDS);
}

test "spawns after its wait, expires, and pays a minute of income" {
    reset();
    nextIn = 1.0;
    update(0.5, 17, 17);
    try std.testing.expect(!active);
    update(0.6, 17, 17);
    try std.testing.expect(active);
    try std.testing.expect(!(x == 8 and y == 8));
    try std.testing.expectEqual(@as(?f32, null), tryClaim(x + 1, y, 10));
    try std.testing.expectEqual(@as(f32, 600), tryClaim(x, y, 10).?);
    try std.testing.expect(!active);
    try std.testing.expectEqual(REWARD_MIN, reward(0));
    // Left alone it goes away on its own.
    nextIn = 0;
    update(0.01, 17, 17);
    try std.testing.expect(active);
    update(LIFETIME + 1, 17, 17);
    try std.testing.expect(!active);
}
