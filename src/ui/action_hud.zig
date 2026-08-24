//! Overlay action HUD that replaced the shop side panel: the meadow gets the
//! full window, and the controls float over it, cursor-first.
//!
//! - Bottom-left: quick-buy bee cross (Elden-Ring-style item cross). Each
//!   slot is one bee type on its d-pad direction; the center button shows and
//!   cycles the buy quantity (x1/x10/x25, also LB/RB).
//! - Bottom-right: upgrade-tree button (Y / T).
//! - Top-left, under the honey readout: passive status rows (Instant Grow,
//!   Aura) and the Prestige card.
//!
//! Every element registers an input block region so clicks on it never fall
//! through to the meadow (camera drag / tile clicks).

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const format = @import("../format.zig");
const locale = @import("../localization.zig");
const icons = @import("icons.zig");
const prompt_icons = @import("prompt_icons.zig");
const input = @import("../input.zig");
const spawners = @import("../spawners.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const prestige_mod = @import("../prestige.zig");
const labs_mod = @import("../labs.zig");
const actions = @import("../actions.zig");
const Textures = @import("../textures.zig").Textures;
const Resources = @import("../resources.zig").Resources;

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    resources: *const Resources,
    // Owned bees per type, indexed by @intFromEnum(components.BeeType).
    beeTypeCounts: [4]usize,
    treeState: *const upgrade_tree.State,
    prestige: *const prestige_mod.PrestigeState,
    labs: *const labs_mod.LabState,
    textures: *const Textures,
};

pub const Action = union(enum) {
    none,
    open_tree,
    open_prestige,
    buy: struct { action: actions.BuyAction, qty: u32 },
};

/// Bee buy quantity, cycled by the cross's center button or LB/RB (persists
/// for the session). Holding Shift while buying still bulk-buys x10+.
/// The x50/x100 steps unlock via the Bulk Order tree node.
pub const BUY_QTYS = [_]u32{ 1, 10, 25, 50, 100 };
const BASE_QTY_COUNT: usize = 3;
var unlockedQtyCount: usize = BASE_QTY_COUNT;
var buyQtyIndex: usize = 0;

/// Sync the unlocked quantity steps with the Bulk Order node level
/// (purchase, load, and run reset all funnel through here).
pub fn setBulkTier(level: u16) void {
    unlockedQtyCount = @min(BUY_QTYS.len, BASE_QTY_COUNT + level);
    if (buyQtyIndex >= unlockedQtyCount) buyQtyIndex = 0;
}

pub fn buyQty() u32 {
    return BUY_QTYS[buyQtyIndex];
}

/// Quantity a purchase should use right now: the selected qty, with Shift
/// held forcing at least x10. Shared by the cross slots and the d-pad /
/// number-key quick buys so every buy path honors the selector.
pub fn effectiveBuyQty() u32 {
    const shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
    return if (shift) @max(buyQty(), 10) else buyQty();
}

/// Step the quantity selection (center button click / gamepad LB/RB).
pub fn cycleBuyQty(delta: i32) void {
    const n: i32 = @intCast(unlockedQtyCount);
    buyQtyIndex = @intCast(@mod(@as(i32, @intCast(buyQtyIndex)) + delta, n));
}

const MARGIN: f32 = 14;
const SLOT: f32 = 60;
const GAP: f32 = 8;
/// Prompt icons draw at 32px (2x the 16px tiles) — crisp and readable.
const PROMPT: f32 = 32;
/// Successful-buy glow duration per slot.
const FLASH_TIME: f32 = 0.3;

var slotFlash: [4]f32 = @splat(0);

/// Trigger the buy glow on a cross slot (0 worker, 1 swift, 2 efficient,
/// 3 gardener). Also called from game.zig for d-pad/number quick buys.
pub fn flashSlot(index: usize) void {
    if (index < slotFlash.len) slotFlash[index] = FLASH_TIME;
}

const SlotSpec = struct {
    beeIndex: usize,
    buyAction: actions.BuyAction,
    cost: f32,
    accent: rl.Color,
    dpad: prompt_icons.Icon,
    unlocked: bool,
};

pub fn draw(ctx: Context) Action {
    var action: Action = .none;
    const mouse = input.pointerPos();
    const dt = rl.getFrameTime();
    for (&slotFlash) |*f| f.* = @max(0, f.* - dt);
    drawBeeCross(ctx, mouse, &action);
    drawTreeButton(ctx, mouse, &action);
    drawPassives(ctx, mouse, &action);
    return action;
}

fn drawBeeCross(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const crossW = SLOT * 3 + GAP * 2;
    const ox = MARGIN;
    const oy = ctx.screenHeight - MARGIN - crossW;
    input.registerBlock(rl.Rectangle.init(ox, oy, crossW, crossW));

    const specs = [_]SlotSpec{
        .{ .beeIndex = 0, .buyAction = .buy_worker_bee, .cost = spawners.BEE_TYPE_COSTS.worker, .accent = C.text, .dpad = .dpad_up, .unlocked = true },
        .{ .beeIndex = 1, .buyAction = .buy_swift_bee, .cost = spawners.BEE_TYPE_COSTS.swift, .accent = C.blue, .dpad = .dpad_left, .unlocked = ctx.treeState.hasEffect(.bee_unlock_swift) },
        .{ .beeIndex = 2, .buyAction = .buy_efficient_bee, .cost = spawners.BEE_TYPE_COSTS.efficient, .accent = C.green, .dpad = .dpad_right, .unlocked = ctx.treeState.hasEffect(.bee_unlock_efficient) },
        .{ .beeIndex = 3, .buyAction = .buy_gardener_bee, .cost = spawners.BEE_TYPE_COSTS.gardener, .accent = C.pink, .dpad = .dpad_down, .unlocked = ctx.treeState.hasEffect(.bee_unlock_gardener) },
    };
    // Slot positions on the cross: up, left, right, down (matches the
    // quick-buy d-pad mapping).
    const positions = [_]rl.Vector2{
        rl.Vector2.init(ox + SLOT + GAP, oy),
        rl.Vector2.init(ox, oy + SLOT + GAP),
        rl.Vector2.init(ox + 2 * (SLOT + GAP), oy + SLOT + GAP),
        rl.Vector2.init(ox + SLOT + GAP, oy + 2 * (SLOT + GAP)),
    };
    for (specs, positions) |spec, pos| {
        drawBeeSlot(ctx, spec, pos, mouse, out);
    }

    // Center: buy quantity, with its prompt as a phone-notification-style
    // badge overlapping the number's top-right corner (the badge's left edge
    // starts at the number's center). Click (or Tab / LB / RB) cycles.
    const center = rl.Rectangle.init(ox + SLOT + GAP, oy + SLOT + GAP, SLOT, SLOT);
    input.registerBlock(center);
    const hovered = rl.checkCollisionPointRec(mouse, center);
    const ccx = center.x + SLOT / 2;
    const ccy = center.y + SLOT / 2;
    // Number on top, prompt below, both centered and sized to match the
    // bee icons.
    const qtyLabel = rl.textFormat("x%d", .{buyQty()});
    const qw = text.measure(qtyLabel, 42);
    const numY = ccy - 36;
    text.drawOutline(qtyLabel, @as(i32, @intFromFloat(ccx)) - @divFloor(qw, 2), @intFromFloat(numY), 42, if (hovered) C.peach else C.yellow, OUTLINE);
    const iconY = ccy - 2;
    if (input.gamepadActive()) {
        prompt_icons.draw(.pad_lb, ccx - PROMPT - 1, iconY, PROMPT);
        prompt_icons.draw(.pad_rb, ccx + 1, iconY, PROMPT);
    } else {
        // The 32x16 TAB tile in a 2x box renders 64x32, centered on the slot.
        prompt_icons.draw(.key_tab, ccx - PROMPT / 2, iconY, PROMPT);
    }
    if (hovered and input.confirmPressed()) cycleBuyQty(1);
}

fn drawBeeSlot(ctx: Context, spec: SlotSpec, pos: rl.Vector2, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(pos.x, pos.y, SLOT, SLOT);
    const cx = rect.x + SLOT / 2;
    const cy = rect.y + SLOT / 2;

    if (!spec.unlocked) {
        // Locked: dark bee silhouette keeps the cross shape and teases the
        // upcoming type.
        rl.drawTexturePro(
            ctx.textures.bee,
            rl.Rectangle.init(0, 0, 32, 32),
            rl.Rectangle.init(cx - 27, cy - 27, 54, 54),
            rl.Vector2.init(0, 0),
            0,
            rl.Color.init(30, 30, 46, 200),
        );
        return;
    }

    const qty = effectiveBuyQty();
    const totalCost = spec.cost * @as(f32, @floatFromInt(qty));
    const afford = ctx.resources.honey >= totalCost;
    const hovered = rl.checkCollisionPointRec(mouse, rect);
    const pressed = hovered and afford and input.confirmDown();

    // Bee sprite, tinted with the type accent (dim when unaffordable), over
    // a soft drop shadow; hovering scales it up as the hover cue.
    // The bee sprite carries generous transparent margins, so it draws well
    // past the slot box to land at a readable visual size.
    const iconSize: f32 = if (pressed) 56 else if (hovered and afford) 66 else 60;
    const tint = if (afford) spec.accent else rl.Color.init(spec.accent.r, spec.accent.g, spec.accent.b, 110);
    const beeDst = rl.Rectangle.init(cx - iconSize / 2, cy - iconSize / 2 - 3, iconSize, iconSize);
    rl.drawTexturePro(
        ctx.textures.bee,
        rl.Rectangle.init(0, 0, 32, 32),
        rl.Rectangle.init(beeDst.x + 2, beeDst.y + 2, iconSize, iconSize),
        rl.Vector2.init(0, 0),
        0,
        rl.Color.init(17, 17, 27, 140),
    );
    rl.drawTexturePro(
        ctx.textures.bee,
        rl.Rectangle.init(0, 0, 32, 32),
        beeDst,
        rl.Vector2.init(0, 0),
        0,
        tint,
    );

    // Successful-buy glow: a bright overlay of the bee that swells and fades.
    const flash = slotFlash[spec.beeIndex];
    if (flash > 0) {
        const t = flash / FLASH_TIME;
        const fs = iconSize * (1 + 0.4 * (1 - t));
        rl.drawTexturePro(
            ctx.textures.bee,
            rl.Rectangle.init(0, 0, 32, 32),
            rl.Rectangle.init(cx - fs / 2, cy - fs / 2 - 3, fs, fs),
            rl.Vector2.init(0, 0),
            0,
            rl.Color.init(255, 246, 190, @intFromFloat(220 * t)),
        );
    }

    // Cost along the slot's bottom edge.
    var cbuf: [32]u8 = undefined;
    const cstr = format.formatShort(totalCost, &cbuf);
    const costLabel = rl.textFormat("%s", .{cstr.ptr});
    const cw = text.measure(costLabel, 16);
    text.drawOutline(costLabel, @as(i32, @intFromFloat(cx)) - @divFloor(cw, 2), @intFromFloat(rect.y + SLOT - 15), 16, if (afford) C.yellow else C.overlay0, OUTLINE);

    // Input prompt, top-left corner: d-pad direction or number key.
    const prompt: prompt_icons.Icon = if (input.gamepadActive()) spec.dpad else prompt_icons.numberKey(spec.beeIndex);
    prompt_icons.draw(prompt, rect.x - 9, rect.y - 9, PROMPT);

    if (hovered and afford and input.confirmPressed()) {
        flashSlot(spec.beeIndex);
        out.* = .{ .buy = .{ .action = spec.buyAction, .qty = qty } };
    }
}

fn drawTreeButton(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const size: f32 = 62;
    const rect = rl.Rectangle.init(ctx.screenWidth - MARGIN - size, ctx.screenHeight - MARGIN - size, size, size);
    input.registerBlock(rect);
    input.registerHotspot(rect);
    const hovered = rl.checkCollisionPointRec(mouse, rect);
    const cxf = rect.x + size / 2;
    const cyf = rect.y + size / 2 + 4;

    // Mini upgrade-tree glyph: a root node branching into two child nodes,
    // with a drop shadow; it grows a little on hover.
    const k: f32 = if (hovered) 1.15 else 1.0;
    const top = rl.Vector2.init(cxf, cyf - 11 * k);
    const bl = rl.Vector2.init(cxf - 11 * k, cyf + 9 * k);
    const br = rl.Vector2.init(cxf + 11 * k, cyf + 9 * k);
    const sh = rl.Color.init(17, 17, 27, 140);
    for ([_]rl.Vector2{ rl.Vector2.init(2, 2), rl.Vector2.init(0, 0) }, 0..) |o, pass| {
        const branch = if (pass == 0) sh else C.overlay1;
        const nodeTop = if (pass == 0) sh else if (hovered) C.pink else C.mauve;
        const nodeKid = if (pass == 0) sh else C.pink;
        rl.drawLineEx(rl.Vector2.init(top.x + o.x, top.y + o.y), rl.Vector2.init(bl.x + o.x, bl.y + o.y), 3, branch);
        rl.drawLineEx(rl.Vector2.init(top.x + o.x, top.y + o.y), rl.Vector2.init(br.x + o.x, br.y + o.y), 3, branch);
        rl.drawCircleV(rl.Vector2.init(top.x + o.x, top.y + o.y), 7 * k, nodeTop);
        rl.drawCircleV(rl.Vector2.init(bl.x + o.x, bl.y + o.y), 5.5 * k, nodeKid);
        rl.drawCircleV(rl.Vector2.init(br.x + o.x, br.y + o.y), 5.5 * k, nodeKid);
    }

    prompt_icons.draw(if (input.gamepadActive()) .pad_y else .key_t, rect.x - 9, rect.y - 9, PROMPT);

    if (hovered and input.confirmPressed()) out.* = .open_tree;
}

/// Bee census row: one icon + owned count per type; locked types show the
/// dark silhouette (same treatment as the cross).
fn drawBeeCensus(ctx: Context, x: f32, y: f32, w: f32, h: f32) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(x, y, w, h);
    input.registerBlock(rect);
    rl.drawRectangleRounded(rect, 0.4, 6, withAlpha(C.surface0, 225));
    rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, 1, C.surface1);

    const accents = [_]rl.Color{ C.text, C.blue, C.green, C.pink };
    const unlocked = [_]bool{
        true,
        ctx.treeState.hasEffect(.bee_unlock_swift),
        ctx.treeState.hasEffect(.bee_unlock_efficient),
        ctx.treeState.hasEffect(.bee_unlock_gardener),
    };
    const cell = w / 4;
    for (accents, unlocked, 0..) |accent, isUnlocked, i| {
        const cx = x + cell * @as(f32, @floatFromInt(i));
        const iconS: f32 = 30;
        const tint = if (isUnlocked) accent else rl.Color.init(30, 30, 46, 200);
        rl.drawTexturePro(
            ctx.textures.bee,
            rl.Rectangle.init(0, 0, 32, 32),
            rl.Rectangle.init(cx + 2, y + (h - iconS) / 2, iconS, iconS),
            rl.Vector2.init(0, 0),
            0,
            tint,
        );
        var nbuf: [32]u8 = undefined;
        const nstr = format.formatShort(@floatFromInt(ctx.beeTypeCounts[i]), &nbuf);
        const label = rl.textFormat("x%s", .{nstr.ptr});
        text.draw(label, @intFromFloat(cx + iconS - 1), @intFromFloat(y + (h - 16) / 2), 16, if (isUnlocked) C.text else C.overlay0);
    }
}

fn drawPassives(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const w: f32 = 250;
    const h: f32 = 34;
    const x: f32 = ctx.screenWidth - w - 12;
    var y: f32 = 12;

    drawBeeCensus(ctx, x, y, w, h);
    y += h + 6;

    if (ctx.treeState.hasEffect(.growth_boost_unlock)) {
        const ready = ctx.resources.canUseGrowthBoost();
        const label = if (ready)
            locale.tr("Instant Grow: ready", "Crescer inst.: pronto")
        else
            rl.textFormat(locale.tr("Instant Grow: %.1fs", "Crescer inst.: %.1fs"), .{ctx.resources.growthBoostCooldown});
        drawPassiveRow(x, y, w, h, .sprout, label, ready, 1.0 - ctx.resources.getCooldownPercent(), C.green);
        y += h + 6;
    }

    if (ctx.treeState.hasEffect(.lab_aura)) {
        drawPassiveRow(x, y, w, h, .aura, rl.textFormat("Aura x%.2f", .{ctx.labs.auraMul}), true, 1.0, C.lavender);
        y += h + 6;
    }

    if (ctx.prestige.hasUnlockedPrestige) {
        const rect = rl.Rectangle.init(x, y, w, h);
        input.registerBlock(rect);
        input.registerHotspot(rect);
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        rl.drawRectangleRounded(rect, 0.4, 6, withAlpha(if (hovered) C.surface1 else C.surface0, 225));
        rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, if (hovered) 2 else 1, if (hovered) C.pink else C.mauve);
        // crown-ish dots
        const cx = @as(i32, @intFromFloat(x + 16));
        const cy = @as(i32, @intFromFloat(y + h / 2));
        rl.drawCircle(cx - 6, cy + 2, 3, C.mauve);
        rl.drawCircle(cx, cy - 3, 3.5, C.pink);
        rl.drawCircle(cx + 6, cy + 2, 3, C.mauve);
        var jbuf: [32]u8 = undefined;
        const jstr = format.formatShort(@floatFromInt(ctx.prestige.royalJelly), &jbuf);
        const label = rl.textFormat(locale.tr("Prestige  RJ %s · x%.2f", "Prestígio  GR %s · x%.2f"), .{ jstr.ptr, ctx.prestige.globalMul() });
        text.draw(label, @intFromFloat(x + 32), @intFromFloat(y + 8), 16, if (hovered) C.pink else C.subtext1);
        if (hovered and input.confirmPressed()) out.* = .open_prestige;
    }
}

fn drawPassiveRow(x: f32, y: f32, w: f32, h: f32, icon: enum { sprout, aura }, label: [:0]const u8, ready: bool, fill: f32, accent: rl.Color) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(x, y, w, h);
    input.registerBlock(rect);
    rl.drawRectangleRounded(rect, 0.4, 6, withAlpha(C.surface0, 225));
    const fillW = (w - 6) * std.math.clamp(fill, 0, 1);
    if (fillW > 1) {
        const fillColor = if (ready) rl.Color.init(accent.r, accent.g, accent.b, 60) else rl.Color.init(88, 91, 112, 70);
        rl.drawRectangleRounded(rl.Rectangle.init(x + 3, y + 3, fillW, h - 6), 0.4, 6, fillColor);
    }
    rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, 1, if (ready) accent else C.surface1);
    const midY = y + h / 2;
    const iconColor = if (ready) accent else C.overlay1;
    switch (icon) {
        .sprout => icons.drawSprout(x + 16, midY + 8, 16, iconColor),
        .aura => icons.drawAura(x + 16, midY, 8, iconColor),
    }
    text.draw(label, @intFromFloat(x + 32), @intFromFloat(y + 8), 16, if (ready) accent else C.subtext1);
}

fn withAlpha(c: rl.Color, a: u8) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, a);
}

/// Outline color for HUD text floating over the meadow (matches hud.zig).
const OUTLINE = rl.Color.init(24, 24, 37, 235);
