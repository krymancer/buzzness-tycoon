//! "Achievement unlocked" banner: slides down from the top edge, holds, and
//! fades. One at a time; further unlocks queue behind it. This is the
//! in-game half of the feedback (Steam's overlay toast is the other) and the
//! only visible signal when playing outside Steam.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const icons = @import("icons.zig");
const input = @import("../input.zig");
const achievements = @import("../achievements.zig");

const MAX_QUEUE = 8;
const SLIDE: f32 = 0.35;
const HOLD: f32 = 3.6;
const FADE: f32 = 0.5;
const TOTAL: f32 = SLIDE + HOLD + FADE;

const PANEL_W: f32 = 380;
const PANEL_H: f32 = 66;
const TOP_MARGIN: f32 = 14;

pub const Manager = struct {
    queue: [MAX_QUEUE]achievements.Id = undefined,
    count: usize = 0,
    /// Seconds the front item has been on screen.
    elapsed: f32 = 0,

    pub fn push(self: *Manager, id: achievements.Id) void {
        if (self.count >= MAX_QUEUE) return;
        self.queue[self.count] = id;
        self.count += 1;
    }

    pub fn active(self: *const Manager) bool {
        return self.count > 0;
    }

    pub fn update(self: *Manager, dt: f32) void {
        if (self.count == 0) return;
        self.elapsed += dt;
        if (self.elapsed >= TOTAL) {
            std.mem.copyForwards(achievements.Id, self.queue[0 .. self.count - 1], self.queue[1..self.count]);
            self.count -= 1;
            self.elapsed = 0;
        }
    }

    fn bounds(self: *const Manager, screenWidth: f32) rl.Rectangle {
        const slide = std.math.clamp(self.elapsed / SLIDE, 0, 1);
        const eased = 1 - (1 - slide) * (1 - slide);
        return rl.Rectangle.init(@round((screenWidth - PANEL_W) / 2), @round(-PANEL_H + (TOP_MARGIN + PANEL_H) * eased), PANEL_W, PANEL_H);
    }

    pub fn clicked(self: *const Manager, screenWidth: f32) bool {
        if (!self.active()) return false;
        if (rl.checkCollisionPointRec(input.pointerPos(), self.bounds(screenWidth)) and input.confirmPressed()) {
            input.consumeConfirm();
            return true;
        }
        return false;
    }

    pub fn draw(self: *const Manager, screenWidth: f32) void {
        if (self.count == 0) return;
        const C = theme.CatppuccinMocha.Color;
        const id = self.queue[0];
        const t = self.elapsed;

        // Ease in from above, hold, then fade out.
        const alpha: f32 = if (t > SLIDE + HOLD) std.math.clamp(1 - (t - SLIDE - HOLD) / FADE, 0, 1) else 1;
        const a: u8 = @intFromFloat(255 * alpha);

        const rect = self.bounds(screenWidth);
        const x = rect.x;
        const y = rect.y;
        input.registerBlock(rect);
        input.registerHotspot(rect);

        rl.drawRectangleRounded(rect, 0.25, 8, withAlpha(C.mantle, @intFromFloat(235 * alpha)));
        rl.drawRectangleRoundedLinesEx(rect, 0.25, 8, 2, withAlpha(C.yellow, a));

        // Crown badge on a honey disc.
        const cx = x + 36;
        const cy = y + PANEL_H / 2;
        rl.drawCircleV(rl.Vector2.init(cx, cy), 22, withAlpha(C.yellow, a));
        icons.drawCrown(cx, cy + 1, 24, withAlpha(C.base, a), withAlpha(C.peach, a));

        const label = achievements.name(id);
        const header = @import("../localization.zig").tr("Achievement unlocked", "Conquista desbloqueada");
        const tx: i32 = @intFromFloat(x + 70);
        text.draw(header, tx, @intFromFloat(y + 11), 15, withAlpha(C.subtext0, a));
        text.draw(label, tx, @intFromFloat(y + 29), 24, withAlpha(C.yellow, a));
    }
};

fn withAlpha(c: rl.Color, a: u8) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, a);
}
