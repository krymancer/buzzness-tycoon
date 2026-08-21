const rl = @import("raylib");
const text = @import("text.zig");
const std = @import("std");
const utils = @import("utils.zig");
const format = @import("format.zig");
const theme = @import("theme.zig");

const LIFETIME: f32 = 1.2;
const RISE_PX_PER_SEC: f32 = 40.0;
const FONT_SIZE: i32 = 22;
// Throttle: merge gains inside this window into the most-recent popup so a
// steady honey flow doesn't spawn one popup per frame.
const MERGE_WINDOW: f32 = 0.25;

pub const FloatingText = struct {
    gridX: f32,
    gridY: f32,
    amount: f32,
    elapsed: f32,
};

/// UI-layer popup ("-10" over a shop button, etc.) — lives in screen
/// coordinates instead of grid coordinates.
pub const ScreenText = struct {
    x: f32,
    y: f32,
    amount: f32, // sign decides look: spends are negative and red, gains green
    elapsed: f32,
};

pub const Manager = struct {
    items: std.ArrayList(FloatingText),
    screenItems: std.ArrayList(ScreenText),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .items = .empty, .screenItems = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        self.items.deinit(self.allocator);
        self.screenItems.deinit(self.allocator);
    }

    pub fn spawn(self: *@This(), gridX: f32, gridY: f32, amount: f32) !void {
        if (self.items.items.len > 0) {
            const last = &self.items.items[self.items.items.len - 1];
            if (last.elapsed < MERGE_WINDOW) {
                last.amount += amount;
                return;
            }
        }
        try self.items.append(self.allocator, .{
            .gridX = gridX,
            .gridY = gridY,
            .amount = amount,
            .elapsed = 0,
        });
    }

    /// Spawn a screen-space popup at (x, y). Negative amounts render as a red
    /// "-N" (a spend), positive as a green "+N".
    pub fn spawnScreen(self: *@This(), x: f32, y: f32, amount: f32) !void {
        try self.screenItems.append(self.allocator, .{
            .x = x,
            .y = y,
            .amount = amount,
            .elapsed = 0,
        });
    }

    pub fn update(self: *@This(), deltaTime: f32) void {
        var i: usize = 0;
        while (i < self.items.items.len) {
            self.items.items[i].elapsed += deltaTime;
            if (self.items.items[i].elapsed >= LIFETIME) {
                _ = self.items.swapRemove(i);
            } else {
                i += 1;
            }
        }
        i = 0;
        while (i < self.screenItems.items.len) {
            self.screenItems.items[i].elapsed += deltaTime;
            if (self.screenItems.items[i].elapsed >= LIFETIME) {
                _ = self.screenItems.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn draw(self: *const @This(), gridOffset: rl.Vector2, gridScale: f32) void {
        for (self.items.items) |ft| {
            const progress = ft.elapsed / LIFETIME;
            const pos = utils.isoToXY(ft.gridX, ft.gridY, 32, 32, gridOffset.x, gridOffset.y, gridScale);
            const tileW = 32 * gridScale;
            const yOffset = RISE_PX_PER_SEC * ft.elapsed;
            const alpha: u8 = @intFromFloat(@max(0.0, 255.0 * (1.0 - progress)));

            // Prefix '+' directly in the number buffer — one format call.
            var buf: [40]u8 = undefined;
            buf[0] = '+';
            const numStr = format.formatShort(ft.amount, buf[1..]);
            const labelLen = 1 + numStr.len;
            buf[labelLen] = 0;
            const label: [:0]const u8 = buf[0..labelLen :0];

            const textWidth = text.measure(label, FONT_SIZE);
            const textX = @as(i32, @intFromFloat(pos.x + tileW / 2.0)) - @divFloor(textWidth, 2);
            const textY = @as(i32, @intFromFloat(pos.y - yOffset));

            var color = theme.CatppuccinMocha.Color.yellow;
            color.a = alpha;
            text.drawShadow(label, textX, textY, FONT_SIZE, color);
        }
    }

    /// Screen-space popups. Draw after the UI so they float above buttons.
    pub fn drawScreen(self: *const @This()) void {
        for (self.screenItems.items) |ft| {
            const progress = ft.elapsed / LIFETIME;
            const yOffset = RISE_PX_PER_SEC * ft.elapsed;
            const alpha: u8 = @intFromFloat(@max(0.0, 255.0 * (1.0 - progress)));

            var buf: [40]u8 = undefined;
            buf[0] = if (ft.amount < 0) '-' else '+';
            const numStr = format.formatShort(@abs(ft.amount), buf[1..]);
            const labelLen = 1 + numStr.len;
            buf[labelLen] = 0;
            const label: [:0]const u8 = buf[0..labelLen :0];

            const textWidth = text.measure(label, FONT_SIZE);
            const textX = @as(i32, @intFromFloat(ft.x)) - @divFloor(textWidth, 2);
            const textY = @as(i32, @intFromFloat(ft.y - yOffset));

            var color = if (ft.amount < 0)
                theme.CatppuccinMocha.Color.red
            else
                theme.CatppuccinMocha.Color.green;
            color.a = alpha;
            text.drawShadow(label, textX, textY, FONT_SIZE, color);
        }
    }
};
