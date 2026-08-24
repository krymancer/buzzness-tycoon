//! Unified pointer input: the OS mouse and a gamepad-driven virtual cursor
//! routed through one API, so every hit-test in the game works with both.
//! The active device follows whichever one the player touched last; while the
//! gamepad drives, a software cursor (in the same logical pixels as
//! rl.getMousePosition after ui_scale's setMouseScale) replaces the mouse.
//!
//! Menus additionally support d-pad "jump" navigation: interactive widgets
//! register their rects each frame (registerHotspot), and a d-pad press moves
//! the cursor to the nearest rect in that direction — the cursor itself is the
//! focus highlight, so widgets need no focus state of their own.

const std = @import("std");
const rl = @import("raylib");
const theme = @import("theme.zig");
const ui_scale = @import("ui_scale.zig");

const PAD: i32 = 0;
const DEADZONE: f32 = 0.18;
/// Full-deflection cursor speed in logical px/s (before the response curve).
const CURSOR_SPEED: f32 = 900;
/// Right-stick camera pan speed, logical px/s.
const PAN_SPEED: f32 = 650;

pub const Device = enum { mouse, gamepad };
pub const Dir = enum { up, down, left, right };

var device: Device = .mouse;
var cursor = rl.Vector2.init(-1, -1); // -1: placed at screen center on first use
var menuMode: bool = false;

const MAX_HOTSPOTS = 128;
var hotspots: [MAX_HOTSPOTS]rl.Rectangle = undefined;
var hotspotCount: usize = 0;
// D-pad jumps read last frame's rects: this frame's aren't registered yet
// when input is polled (immediate-mode UI draws after input handling).
var prevHotspots: [MAX_HOTSPOTS]rl.Rectangle = undefined;
var prevHotspotCount: usize = 0;

/// Poll devices, advance the virtual cursor, and (in menus) handle d-pad
/// jumps. Call once per frame before any input handling or drawing.
/// `menu` marks modal/menu contexts: d-pad navigates instead of quick-buying,
/// and the right stick scrolls instead of panning the camera.
pub fn beginFrame(menu: bool) void {
    menuMode = menu;
    prevHotspots = hotspots;
    prevHotspotCount = hotspotCount;
    hotspotCount = 0;

    if (!rl.isGamepadAvailable(PAD)) {
        device = .mouse;
        return;
    }

    const stick = stickVector(.left_x, .left_y);
    if (gamepadTouched(stick)) {
        device = .gamepad;
    } else if (mouseTouched()) {
        device = .mouse;
    }
    if (device != .gamepad) return;

    if (cursor.x < 0) cursor = rl.Vector2.init(ui_scale.width() / 2, ui_scale.height() / 2);
    // Ease-in response: slow near the center for pixel precision, fast at
    // full deflection to cross the screen quickly.
    const mag = @sqrt(stick.x * stick.x + stick.y * stick.y);
    const curved = mag * mag * CURSOR_SPEED * rl.getFrameTime();
    if (mag > 0) {
        cursor.x += stick.x / mag * curved;
        cursor.y += stick.y / mag * curved;
    }
    cursor.x = std.math.clamp(cursor.x, 0, ui_scale.width() - 1);
    cursor.y = std.math.clamp(cursor.y, 0, ui_scale.height() - 1);

    if (menuMode) {
        if (dpadPressed(.up)) jumpCursor(0, -1);
        if (dpadPressed(.down)) jumpCursor(0, 1);
        if (dpadPressed(.left)) jumpCursor(-1, 0);
        if (dpadPressed(.right)) jumpCursor(1, 0);
    }
}

/// Pointer position in logical pixels: the virtual cursor while the gamepad
/// drives, the (already ui_scale-d) mouse otherwise.
pub fn pointerPos() rl.Vector2 {
    return if (device == .gamepad) cursor else rl.getMousePosition();
}

pub fn gamepadActive() bool {
    return device == .gamepad;
}

/// Primary click: mouse left button or gamepad A.
pub fn confirmPressed() bool {
    return rl.isMouseButtonPressed(rl.MouseButton.left) or padPressed(.right_face_down);
}

pub fn confirmDown() bool {
    return rl.isMouseButtonDown(rl.MouseButton.left) or padDown(.right_face_down);
}

pub fn confirmReleased() bool {
    return rl.isMouseButtonReleased(rl.MouseButton.left) or padReleased(.right_face_down);
}

/// Gamepad B: back/close, treated like Escape.
pub fn cancelPressed() bool {
    return padPressed(.right_face_right);
}

/// Gamepad Start (menu button).
pub fn startPressed() bool {
    return padPressed(.middle_right);
}

/// Gamepad Y: upgrade tree toggle.
pub fn treePressed() bool {
    return padPressed(.right_face_up);
}

/// Gamepad X: plant on the hovered tile.
pub fn plantPressed() bool {
    return padPressed(.right_face_left);
}

pub fn dpadPressed(d: Dir) bool {
    return padPressed(switch (d) {
        .up => .left_face_up,
        .down => .left_face_down,
        .left => .left_face_left,
        .right => .left_face_right,
    });
}

/// Shoulder buttons: -1 (LB) / +1 (RB), for cycling the buy quantity.
pub fn shoulderCycle() i32 {
    var d: i32 = 0;
    if (padPressed(.left_trigger_1)) d -= 1;
    if (padPressed(.right_trigger_1)) d += 1;
    return d;
}

/// Trigger zoom: +1 while RT is held, -1 while LT is held.
pub fn zoomAxis() f32 {
    var z: f32 = 0;
    if (padDown(.right_trigger_2)) z += 1;
    if (padDown(.left_trigger_2)) z -= 1;
    return z;
}

/// Right-stick camera pan (world), in logical px for this frame.
pub fn cameraPan() rl.Vector2 {
    if (device != .gamepad) return rl.Vector2.init(0, 0);
    const stick = stickVector(.right_x, .right_y);
    const step = PAN_SPEED * rl.getFrameTime();
    return rl.Vector2.init(stick.x * step, stick.y * step);
}

/// Scroll input for menus: mouse wheel plus (in menu mode) the right stick.
pub fn scrollV() rl.Vector2 {
    var v = rl.getMouseWheelMoveV();
    if (menuMode and device == .gamepad) {
        // Consumers scale wheel units by ~40px, so emit stick motion in
        // wheel units for an ~800 logical px/s scroll at full deflection.
        const stick = stickVector(.right_x, .right_y);
        const k = 20 * rl.getFrameTime();
        v.x -= stick.x * k;
        v.y -= stick.y * k;
    }
    return v;
}

/// Mark a rect as clickable this frame so d-pad navigation can jump to it.
pub fn registerHotspot(rect: rl.Rectangle) void {
    if (hotspotCount >= MAX_HOTSPOTS) return;
    hotspots[hotspotCount] = rect;
    hotspotCount += 1;
}

/// Draw the virtual cursor. Call last in the frame, inside ui_scale scope.
pub fn drawCursor() void {
    if (device != .gamepad) return;
    const C = theme.CatppuccinMocha.Color;
    const x = cursor.x;
    const y = cursor.y;
    // Classic pointer triangle with a soft drop shadow.
    const tip = rl.Vector2.init(x, y);
    const a = rl.Vector2.init(x + 4.5, y + 17);
    const b = rl.Vector2.init(x + 12.5, y + 12);
    const sh = rl.Vector2.init(2, 2);
    rl.drawTriangle(rl.Vector2.init(tip.x + sh.x, tip.y + sh.y), rl.Vector2.init(a.x + sh.x, a.y + sh.y), rl.Vector2.init(b.x + sh.x, b.y + sh.y), rl.Color.init(17, 17, 27, 110));
    rl.drawTriangle(tip, a, b, C.yellow);
    rl.drawTriangleLines(tip, a, b, C.crust);
}

fn padPressed(b: rl.GamepadButton) bool {
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonPressed(PAD, b);
}

fn padDown(b: rl.GamepadButton) bool {
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonDown(PAD, b);
}

fn padReleased(b: rl.GamepadButton) bool {
    return rl.isGamepadAvailable(PAD) and rl.isGamepadButtonReleased(PAD, b);
}

/// Deadzoned axis, rescaled so motion ramps from 0 at the deadzone edge.
fn axis(a: rl.GamepadAxis) f32 {
    const v = rl.getGamepadAxisMovement(PAD, a);
    const m = @abs(v);
    if (m < DEADZONE) return 0;
    return std.math.sign(v) * (m - DEADZONE) / (1 - DEADZONE);
}

fn stickVector(ax: rl.GamepadAxis, ay: rl.GamepadAxis) rl.Vector2 {
    return rl.Vector2.init(axis(ax), axis(ay));
}

fn gamepadTouched(leftStick: rl.Vector2) bool {
    if (leftStick.x != 0 or leftStick.y != 0) return true;
    if (axis(.right_x) != 0 or axis(.right_y) != 0) return true;
    inline for (@typeInfo(rl.GamepadButton).@"enum".fields) |f| {
        const b: rl.GamepadButton = @enumFromInt(f.value);
        if (b != .unknown and rl.isGamepadButtonDown(PAD, b)) return true;
    }
    return false;
}

fn mouseTouched() bool {
    const d = rl.getMouseDelta();
    if (@abs(d.x) > 3 or @abs(d.y) > 3) return true;
    return rl.isMouseButtonPressed(rl.MouseButton.left) or
        rl.isMouseButtonPressed(rl.MouseButton.right);
}

/// Move the cursor to the best hotspot in direction (dx, dy): the candidate
/// with the shortest forward distance, penalizing sideways offset, within a
/// cone so "down" never selects something purely to the side.
fn jumpCursor(dx: f32, dy: f32) void {
    var best: ?rl.Vector2 = null;
    var bestScore: f32 = std.math.floatMax(f32);
    for (prevHotspots[0..prevHotspotCount]) |r| {
        const c = rl.Vector2.init(r.x + r.width / 2, r.y + r.height / 2);
        const vx = c.x - cursor.x;
        const vy = c.y - cursor.y;
        const forward = vx * dx + vy * dy;
        if (forward < 6) continue; // behind or effectively level with the cursor
        const side = @abs(vx * dy) + @abs(vy * dx);
        if (side > forward * 1.3 + 40) continue;
        const score = forward + side * 2;
        if (score < bestScore) {
            bestScore = score;
            best = c;
        }
    }
    if (best) |c| cursor = c;
}
