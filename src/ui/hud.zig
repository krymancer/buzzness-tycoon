const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const theme = @import("../theme.zig");
const config = @import("../config.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");
const input = @import("../input.zig");

pub const OUTLINE = rl.Color.init(24, 24, 37, 235);

pub const Hud = struct {
    pub fn init() @This() {
        theme.applyCatppuccinMochaTheme();
        return .{};
    }
    pub fn deinit(_: @This()) void {}

    /// A stable-width stat card. At capacity the rate explicitly describes
    /// production being lost, rather than suggesting the balance is growing.
    /// Clicking the capacity warning opens Storage in the upgrade tree.
    pub fn draw(_: @This(), resources: *const Resources, beehiveFactor: f32, nightFactor: f32, nightMul: f32, width: f32, enabled: bool) bool {
        const C = theme.CatppuccinMocha.Color;
        const w = @min(440, @max(260, width * 0.48 - 20));
        const full = config.honey_cap_enabled and resources.isAtCapacity();
        const rect = rl.Rectangle.init(12, 12, w, if (full) 153 else 124);
        input.registerBlock(rect);
        rl.drawRectangleRounded(rect, 0.12, 6, rl.Color.init(C.mantle.r, C.mantle.g, C.mantle.b, 235));
        rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, 1, if (full) C.peach else C.surface1);
        var hb: [32]u8 = undefined;
        var cb: [32]u8 = undefined;
        var rb: [32]u8 = undefined;
        var fb: [32]u8 = undefined;
        const amount = format.formatShort(resources.honey, &hb);
        const capacity = format.formatShort(resources.honeyCapacity, &cb);
        const amountLabel = if (config.honey_cap_enabled) rl.textFormat("%s / %s", .{ amount.ptr, capacity.ptr }) else amount;
        text.draw(amountLabel, 24, 20, 30, C.yellow);
        if (config.honey_cap_enabled) {
            rl.drawRectangleRounded(rl.Rectangle.init(24, 58, w - 24, 6), 0.5, 4, C.surface1);
            const pct = resources.getCapacityPercent();
            const safePct = if (std.math.isFinite(pct)) std.math.clamp(pct, 0, 1) else @as(f32, 1);
            const fill = (w - 24) * safePct;
            if (fill > 1) rl.drawRectangleRounded(rl.Rectangle.init(24, 58, fill, 6), 0.5, 4, if (full) C.peach else C.yellow);
        }
        const rate = if (resources.honeyPerSec < 1000) (std.fmt.bufPrintZ(&rb, "{d:.1}", .{resources.honeyPerSec}) catch "?") else format.formatShort(resources.honeyPerSec, &rb);
        const rateLabel = if (full)
            rl.textFormat(locale.tr("%s honey/s overflowing", "%s mel/s desperdiçado"), .{rate.ptr})
        else
            rl.textFormat(locale.tr("+%s honey/s", "+%s mel/s"), .{rate.ptr});
        text.draw(rateLabel, 24, 72, 19, if (full) C.peach else C.green);
        const factor = if (beehiveFactor < 1000) (std.fmt.bufPrintZ(&fb, "{d:.1}", .{beehiveFactor}) catch "?") else format.formatShort(beehiveFactor, &fb);
        const chips = if (nightFactor > 0.01)
            rl.textFormat(locale.tr("Hive x%s · Night x%.2f", "Colmeia x%s · Noite x%.2f"), .{ factor.ptr, nightMul })
        else
            rl.textFormat(locale.tr("Hive x%s", "Colmeia x%s"), .{factor.ptr});
        text.draw(chips, 24, 101, 15, C.subtext1);
        if (full) {
            const warning = rl.Rectangle.init(20, 133, w - 16, 24);
            if (enabled) input.registerHotspot(warning);
            text.draw(locale.tr("Storage full · increase capacity", "Armazém cheio · aumentar limite"), 24, 134, 15, C.peach);
            if (enabled and rl.checkCollisionPointRec(input.pointerPos(), warning) and input.confirmPressed()) {
                input.consumeConfirm();
                return true;
            }
        }
        return false;
    }
};
