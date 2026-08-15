//! Game clock indirection. Normally passes through to raylib's real-time
//! clock, but during frame-dump capture (BT_CAPTURE) it advances by a fixed
//! timestep per rendered frame so the recording is smooth and deterministic
//! regardless of how slowly the PNG encode runs.
const rl = @import("raylib");

/// When set (seconds), the clock is virtual and advances by this amount each
/// frame via `advance()`. null = real wall-clock time.
pub var fixedDt: ?f32 = null;
var virtual: f64 = 0;

/// Elapsed seconds — virtual during capture, else raylib's real clock.
pub fn time() f64 {
    return if (fixedDt != null) virtual else rl.getTime();
}

/// Frame delta — the fixed capture step, else raylib's measured frame time.
pub fn frameTime() f32 {
    return fixedDt orelse rl.getFrameTime();
}

/// Advance the virtual clock one frame. No-op when using the real clock.
pub fn advance() void {
    if (fixedDt) |dt| virtual += dt;
}
