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
const assets = @import("assets.zig");

const PAD: i32 = 0;
const DEADZONE: f32 = 0.18;
/// Full-deflection cursor speed in logical px/s (before the response curve).
const CURSOR_SPEED: f32 = 900;
/// Right-stick camera pan speed, logical px/s.
const PAN_SPEED: f32 = 650;
/// Step mode (tile snap): deflections up to this step tile-by-tile; only a
/// harder push moves the cursor freely.
const STEP_ZONE: f32 = 0.55;
/// Key-repeat style timing for held tile steps.
const STEP_REPEAT_FIRST: f32 = 0.30;
const STEP_REPEAT: f32 = 0.15;

pub const Device = enum { mouse, gamepad };
pub const Dir = enum { up, down, left, right };

var device: Device = .mouse;
var cursor = rl.Vector2.init(-1, -1); // -1: placed at screen center on first use
var menuMode: bool = false;

// Tile-step state (see beginFrame). stepMode is set by the game when the
// cursor sits on the grid with snap enabled; a step becomes "eligible" only
// after the stick returns to rest, so easing off from a free flight through
// the step zone never fires a spurious step.
var stepMode: bool = false;
var stepArmed: bool = false;
var stepEligible: bool = true;
var stepRepeatTimer: f32 = 0;
var pendingStep: ?rl.Vector2 = null;

const MAX_HOTSPOTS = 128;
var hotspots: [MAX_HOTSPOTS]rl.Rectangle = undefined;
var hotspotCount: usize = 0;
// D-pad jumps read last frame's rects: this frame's aren't registered yet
// when input is polled (immediate-mode UI draws after input handling).
var prevHotspots: [MAX_HOTSPOTS]rl.Rectangle = undefined;
var prevHotspotCount: usize = 0;

// Screen regions owned by HUD/UI this frame (same one-frame-behind scheme
// as hotspots). World input (camera drag, tile clicks) is suppressed while
// the pointer is over one.
const MAX_BLOCKS = 32;
var blockRects: [MAX_BLOCKS]rl.Rectangle = undefined;
var blockCount: usize = 0;
var prevBlockRects: [MAX_BLOCKS]rl.Rectangle = undefined;
var prevBlockCount: usize = 0;

/// Poll devices, advance the virtual cursor, and (in menus) handle d-pad
/// jumps. Call once per frame before any input handling or drawing.
/// `menu` marks modal/menu contexts: d-pad navigates instead of quick-buying,
/// and the right stick scrolls instead of panning the camera.
pub fn beginFrame(menu: bool) void {
    menuMode = menu;
    prevHotspots = hotspots;
    prevHotspotCount = hotspotCount;
    hotspotCount = 0;
    prevBlockRects = blockRects;
    prevBlockCount = blockCount;
    blockCount = 0;

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
    const dt = rl.getFrameTime();
    const mag = @sqrt(stick.x * stick.x + stick.y * stick.y);
    pendingStep = null;
    if (mag == 0) {
        stepArmed = false;
        stepEligible = true;
    } else if (stepMode and mag <= STEP_ZONE) {
        // Gentle deflection over the grid: discrete tile steps with
        // key-repeat timing instead of free movement, so neighbors are easy
        // to hit precisely.
        const dir = rl.Vector2.init(stick.x / mag, stick.y / mag);
        if (!stepArmed) {
            if (stepEligible) pendingStep = dir;
            stepArmed = true;
            stepRepeatTimer = STEP_REPEAT_FIRST;
        } else if (stepEligible) {
            stepRepeatTimer -= dt;
            if (stepRepeatTimer <= 0) {
                pendingStep = dir;
                stepRepeatTimer = STEP_REPEAT;
            }
        }
    } else {
        // Free flight, with an ease-in response: slow near the zone edge for
        // precision, fast at full deflection to cross the screen quickly.
        stepArmed = false;
        stepEligible = false;
        var eff = mag;
        if (stepMode) eff = (mag - STEP_ZONE) / (1 - STEP_ZONE);
        const curved = eff * eff * CURSOR_SPEED * dt;
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

/// Gamepad Y or keyboard T: upgrade tree toggle.
pub fn treePressed() bool {
    return padPressed(.right_face_up) or rl.isKeyPressed(rl.KeyboardKey.t);
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

/// Buy-quantity cycling: -1 (LB) / +1 (RB or keyboard Tab).
pub fn shoulderCycle() i32 {
    var d: i32 = 0;
    if (padPressed(.left_trigger_1)) d -= 1;
    if (padPressed(.right_trigger_1) or rl.isKeyPressed(rl.KeyboardKey.tab)) d += 1;
    return d;
}

/// Zoom: +1 while RT or `=` is held, -1 while LT or `-` is held. The bare
/// keys only — Cmd/Ctrl +/- belongs to the UI scale.
pub fn zoomAxis() f32 {
    var z: f32 = 0;
    if (padDown(.right_trigger_2)) z += 1;
    if (padDown(.left_trigger_2)) z -= 1;
    if (!modDown()) {
        if (rl.isKeyDown(rl.KeyboardKey.equal) or rl.isKeyDown(rl.KeyboardKey.kp_add)) z += 1;
        if (rl.isKeyDown(rl.KeyboardKey.minus) or rl.isKeyDown(rl.KeyboardKey.kp_subtract)) z -= 1;
    }
    return std.math.clamp(z, -1, 1);
}

/// Camera pan (world): right stick and/or WASD/arrow keys, in logical px
/// for this frame.
pub fn cameraPan() rl.Vector2 {
    var v = rl.Vector2.init(0, 0);
    if (device == .gamepad) {
        const stick = stickVector(.right_x, .right_y);
        v.x += stick.x;
        v.y += stick.y;
    }
    if (rl.isKeyDown(rl.KeyboardKey.a) or rl.isKeyDown(rl.KeyboardKey.left)) v.x -= 1;
    if (rl.isKeyDown(rl.KeyboardKey.d) or rl.isKeyDown(rl.KeyboardKey.right)) v.x += 1;
    if (rl.isKeyDown(rl.KeyboardKey.w) or rl.isKeyDown(rl.KeyboardKey.up)) v.y -= 1;
    if (rl.isKeyDown(rl.KeyboardKey.s) or rl.isKeyDown(rl.KeyboardKey.down)) v.y += 1;
    const step = PAN_SPEED * rl.getFrameTime();
    return rl.Vector2.init(std.math.clamp(v.x, -1, 1) * step, std.math.clamp(v.y, -1, 1) * step);
}

/// Quick-buy chord for one bee type: d-pad direction or number key.
/// up/1 worker, left/2 swift, right/3 efficient, down/4 gardener.
pub fn quickBuyPressed(d: Dir) bool {
    if (dpadPressed(d)) return true;
    return rl.isKeyPressed(switch (d) {
        .up => rl.KeyboardKey.one,
        .left => rl.KeyboardKey.two,
        .right => rl.KeyboardKey.three,
        .down => rl.KeyboardKey.four,
    });
}

/// Left-stick X for slider adjustment while a gamepad drags a widget.
pub fn menuStickX() f32 {
    if (device != .gamepad) return 0;
    return stickVector(.left_x, .left_y).x;
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

/// Mark a rect as HUD-owned this frame: while the pointer is over it, world
/// input (camera drag, tile clicks, tile snap) is suppressed.
pub fn registerBlock(rect: rl.Rectangle) void {
    if (blockCount >= MAX_BLOCKS) return;
    blockRects[blockCount] = rect;
    blockCount += 1;
}

/// Whether the pointer is over a HUD region registered last frame.
pub fn pointerInUi() bool {
    const p = pointerPos();
    for (prevBlockRects[0..prevBlockCount]) |r| {
        if (rl.checkCollisionPointRec(p, r)) return true;
    }
    return false;
}

/// Enable tile-step mode: the game sets this while the cursor sits on the
/// grid with snap enabled (takes effect next frame). Off, the stick moves
/// the cursor freely at every deflection (menus, panels, snap disabled).
pub fn setStepMode(active: bool) void {
    if (stepMode != active) stepArmed = false;
    stepMode = active;
}

/// The tile-step fired this frame, as a normalized stick direction, or null.
/// Consume it once per frame after beginFrame.
pub fn takeStep() ?rl.Vector2 {
    defer pendingStep = null;
    return pendingStep;
}

/// Teleport the virtual cursor (tile stepping lands it on a tile center).
pub fn warpCursor(pos: rl.Vector2) void {
    if (device == .gamepad) cursor = pos;
}

/// Ease the cursor toward `target` (tile magnetism) while the left stick is
/// idle, so a released stick settles on the tile center instead of between
/// tiles. No-op for the mouse or while the player is actively steering.
pub fn magnetPull(target: rl.Vector2) void {
    if (device != .gamepad) return;
    const stick = stickVector(.left_x, .left_y);
    if (stick.x != 0 or stick.y != 0) return;
    const k = @min(1.0, 12 * rl.getFrameTime());
    cursor.x += (target.x - cursor.x) * k;
    cursor.y += (target.y - cursor.y) * k;
}

var cursorTex: ?rl.Texture = null;

/// Draw the pointer (mouse and gamepad alike — the OS cursor is hidden).
/// Call last in the frame, inside ui_scale scope. Uses the 16x16 pixel-art
/// cursor sprite; falls back to a drawn triangle if it fails to load.
pub fn drawCursor() void {
    const p = pointerPos();
    if (cursorTex == null) {
        cursorTex = assets.loadTextureFromMemory(assets.ui_cursor_png) catch null;
    }
    if (cursorTex) |tex| {
        // The arrow's tip sits at ~(2,1) in the sprite; offset so the tip
        // lands exactly on the pointer position. x2 scale, point-filtered.
        const s: f32 = 2;
        rl.drawTextureEx(tex, rl.Vector2.init(p.x - 2 * s, p.y - 1 * s), 0, s, rl.Color.white);
        return;
    }
    const C = theme.CatppuccinMocha.Color;
    const tip = rl.Vector2.init(p.x, p.y);
    const a = rl.Vector2.init(p.x + 4.5, p.y + 17);
    const b = rl.Vector2.init(p.x + 12.5, p.y + 12);
    rl.drawTriangle(tip, a, b, C.yellow);
    rl.drawTriangleLines(tip, a, b, C.crust);
}

pub fn deinit() void {
    if (cursorTex) |tex| rl.unloadTexture(tex);
    cursorTex = null;
}

fn modDown() bool {
    return rl.isKeyDown(rl.KeyboardKey.left_super) or rl.isKeyDown(rl.KeyboardKey.right_super) or
        rl.isKeyDown(rl.KeyboardKey.left_control) or rl.isKeyDown(rl.KeyboardKey.right_control);
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

/// Deadzoned stick as a vector, with a RADIAL deadzone: the vector's length
/// is rescaled to ramp from 0 at the deadzone edge, but its angle is kept
/// exactly. A per-axis deadzone would zero the smaller component of gentle
/// diagonal pushes, collapsing them to the four cardinals — which made the
/// isometric grid's shallow-angle neighbors unreachable by tile-stepping.
fn stickVector(ax: rl.GamepadAxis, ay: rl.GamepadAxis) rl.Vector2 {
    const rx = rl.getGamepadAxisMovement(PAD, ax);
    const ry = rl.getGamepadAxisMovement(PAD, ay);
    const m = @sqrt(rx * rx + ry * ry);
    if (m < DEADZONE) return rl.Vector2.init(0, 0);
    const k = (@min(m, 1) - DEADZONE) / (1 - DEADZONE) / m;
    return rl.Vector2.init(rx * k, ry * k);
}

fn gamepadTouched(leftStick: rl.Vector2) bool {
    if (leftStick.x != 0 or leftStick.y != 0) return true;
    const right = stickVector(.right_x, .right_y);
    if (right.x != 0 or right.y != 0) return true;
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
