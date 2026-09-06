const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const input = @import("../input.zig");

pub const OUTLINE = rl.Color.init(24, 24, 37, 235);

pub const Hud = struct {
    pub fn init() @This() {
        theme.applyCatppuccinMochaTheme();
        return .{};
    }
    pub fn deinit(_: @This()) void {}

    /// Keep the meadow visible: one thin resource strip, with secondary
    /// multipliers on hover (also reachable by the controller cursor).
    /// The strip buys the next storage level; hover shows its price.
    pub fn draw(_: @This(), resources: *const Resources, beehiveFactor: f32, nightFactor: f32, nightMul: f32, width: f32, enabled: bool, tree: *const upgrade_tree.State, costMul: f32, ascensions: u32) bool {
        const C = theme.CatppuccinMocha.Color;
        const storage = upgrade_tree.findNode(upgrade_tree.STORAGE_ID).?;
        const storageCost = tree.nextCost(storage, costMul);
        const canUpgrade = tree.canBuy(storage, ascensions) and resources.honey >= storageCost;
        const w = @min(440, @max(260, width * 0.48 - 20));
        const full = config.honey_cap_enabled and resources.isAtCapacity();
        const rect = rl.Rectangle.init(12, 12, w, 48);
        input.registerBlock(rect);
        if (enabled) input.registerHotspot(rect);
        const hovered = enabled and rl.checkCollisionPointRec(input.pointerPos(), rect);
        rl.drawRectangleRounded(rect, 0.18, 6, rl.Color.init(C.mantle.r, C.mantle.g, C.mantle.b, 215));
        var hb: [32]u8 = undefined;
        var cb: [32]u8 = undefined;
        var rb: [32]u8 = undefined;
        var fb: [32]u8 = undefined;
        const amount = format.formatShort(resources.honey, &hb);
        const capacity = format.formatShort(resources.honeyCapacity, &cb);
        const amountLabel = if (config.honey_cap_enabled) rl.textFormat("%s / %s", .{ amount.ptr, capacity.ptr }) else amount;
        var amountSize: i32 = 25;
        while (amountSize > 14 and @as(f32, @floatFromInt(text.measure(amountLabel, amountSize))) > w - 145) amountSize -= 1;
        text.draw(amountLabel, 24, 19, amountSize, C.yellow);
        const rate = if (resources.honeyPerSec < 1000) (std.fmt.bufPrintZ(&rb, "{d:.1}", .{resources.honeyPerSec}) catch "?") else format.formatShort(resources.honeyPerSec, &rb);
        const rateLabel = if (full) locale.tr("Full · Storage", "Cheio · Armazém") else rl.textFormat("+%s/s", .{rate.ptr});
        const rateWidth: f32 = @floatFromInt(text.measure(rateLabel, 17));
        text.draw(rateLabel, @intFromFloat(12 + w - 12 - rateWidth), 23, 17, if (full) C.peach else C.green);
        if (config.honey_cap_enabled) {
            rl.drawRectangleRounded(rl.Rectangle.init(24, 50, w - 24, 3), 0.5, 4, C.surface1);
            const pct = resources.getCapacityPercent();
            const safePct = if (std.math.isFinite(pct)) std.math.clamp(pct, 0, 1) else @as(f32, 1);
            const fill = (w - 24) * safePct;
            if (fill > 1) rl.drawRectangleRounded(rl.Rectangle.init(24, 50, fill, 3), 0.5, 4, if (full) C.peach else C.yellow);
        }
        if (hovered) {
            const details = rl.Rectangle.init(12, 66, w, 88);
            input.registerBlock(details);
            rl.drawRectangleRounded(details, 0.1, 6, C.mantle);
            text.draw(if (full) rl.textFormat(locale.tr("%s honey/s overflowing", "%s mel/s desperdiçado"), .{rate.ptr}) else rl.textFormat(locale.tr("+%s honey/s", "+%s mel/s"), .{rate.ptr}), 24, 77, 18, if (full) C.peach else C.green);
            const factor = if (beehiveFactor < 1000) (std.fmt.bufPrintZ(&fb, "{d:.1}", .{beehiveFactor}) catch "?") else format.formatShort(beehiveFactor, &fb);
            const chips = if (nightFactor > 0.01) rl.textFormat(locale.tr("Hive x%s · Night x%.2f", "Colmeia x%s · Noite x%.2f"), .{ factor.ptr, nightMul }) else rl.textFormat(locale.tr("Hive x%s", "Colmeia x%s"), .{factor.ptr});
            text.draw(chips, 24, 103, 16, C.subtext1);
            var sb: [32]u8 = undefined;
            text.draw(rl.textFormat(locale.tr("Click: storage + · %s honey", "Clique: armazém + · %s mel"), .{format.formatShort(storageCost, &sb).ptr}), 24, 128, 14, if (canUpgrade) C.yellow else C.subtext0);
        }
        if (hovered and canUpgrade and input.confirmPressed()) {
            input.consumeConfirm();
            return true;
        }
        return false;
    }
};
