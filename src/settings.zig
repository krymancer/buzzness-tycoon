//! Player-facing settings that aren't game state: window mode (and the code
//! that switches it). Language lives in localization.zig, UI scale in
//! ui_scale.zig, volume in audio.zig; the Options screen edits all of them
//! and game.zig persists them in the save file.

const rl = @import("raylib");

pub const WindowMode = enum(u8) {
    /// Decorated, centred 1280x720 window.
    windowed,
    /// Undecorated window covering the monitor. Alt-Tab / Cmd-Tab friendly.
    borderless,
    /// Exclusive fullscreen (GLFW monitor mode). True fullscreen, but the
    /// window manager is sidelined (Alt-Tab quirks).
    fullscreen,

    pub fn fromInt(v: u8) WindowMode {
        return switch (v) {
            0 => .windowed,
            2 => .fullscreen,
            else => .borderless,
        };
    }
};

/// The mode the player chose (persisted). Default: borderless.
pub var windowMode: WindowMode = .borderless;
/// What the OS window is actually in right now.
var applied: WindowMode = .windowed;

pub fn current() WindowMode {
    return applied;
}

/// Switch the live window to `mode` (no-op if already there) and remember it.
pub fn apply(mode: WindowMode) void {
    windowMode = mode;
    if (mode == applied) return;

    // Always pass through plain windowed so transitions compose.
    switch (applied) {
        .fullscreen => {
            rl.toggleFullscreen();
            centreWindow();
        },
        .borderless => leaveBorderless(),
        .windowed => {},
    }
    switch (mode) {
        .windowed => centreWindow(),
        .borderless => enterBorderless(),
        .fullscreen => {
            const monitor = rl.getCurrentMonitor();
            const mw = rl.getMonitorWidth(monitor);
            const mh = rl.getMonitorHeight(monitor);
            if (mw > 0 and mh > 0) rl.setWindowSize(mw, mh);
            rl.toggleFullscreen();
        },
    }
    applied = mode;
}

/// Alt+Enter: windowed <-> the player's fullscreen-ish preference.
pub fn toggleQuick() void {
    if (applied == .windowed) {
        apply(if (windowMode == .windowed) .borderless else windowMode);
    } else {
        apply(.windowed);
    }
}

fn centreWindow() void {
    const monitor = rl.getCurrentMonitor();
    const mpos = rl.getMonitorPosition(monitor);
    const mw = rl.getMonitorWidth(monitor);
    const mh = rl.getMonitorHeight(monitor);
    rl.clearWindowState(.{ .window_undecorated = true });
    rl.setWindowSize(1280, 720);
    rl.setWindowPosition(@as(i32, @intFromFloat(mpos.x)) + @divFloor(mw - 1280, 2), @as(i32, @intFromFloat(mpos.y)) + @divFloor(mh - 720, 2));
}

/// Cover the current monitor with an undecorated, normal-level window. Done
/// by hand: raylib 6.0's ToggleBorderlessWindowed() still calls
/// glfwSetWindowMonitor() with a real monitor (exclusive mode, which
/// captures the display on macOS; raylib #3865).
fn enterBorderless() void {
    const monitor = rl.getCurrentMonitor();
    const mpos = rl.getMonitorPosition(monitor);
    const mw = rl.getMonitorWidth(monitor);
    const mh = rl.getMonitorHeight(monitor);
    if (mw <= 0 or mh <= 0) return;
    const mx: i32 = @intFromFloat(mpos.x);
    const my: i32 = @intFromFloat(mpos.y);

    rl.setWindowState(.{ .window_undecorated = true });
    rl.setWindowSize(mw, mh);
    rl.setWindowPosition(mx, my);
    // macOS keeps normal windows below the menu bar: if the WM pushed us
    // down, give up that strip instead of letting the bottom get clipped.
    const got = rl.getWindowPosition();
    const pushed: i32 = @as(i32, @intFromFloat(got.y)) - my;
    if (pushed > 0) rl.setWindowSize(mw, mh - pushed);
    rl.setWindowFocused();
}

fn leaveBorderless() void {
    centreWindow();
}
