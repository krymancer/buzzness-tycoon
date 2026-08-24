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
pub const BUY_QTYS = [_]u32{ 1, 10, 25 };
var buyQtyIndex: usize = 0;

pub fn buyQty() u32 {
    return BUY_QTYS[buyQtyIndex];
}

/// Step the quantity selection (center button click / gamepad LB/RB).
pub fn cycleBuyQty(delta: i32) void {
    const n: i32 = @intCast(BUY_QTYS.len);
    buyQtyIndex = @intCast(@mod(@as(i32, @intCast(buyQtyIndex)) + delta, n));
}

const MARGIN: f32 = 14;
const SLOT: f32 = 60;
const GAP: f32 = 8;
/// Prompt icons draw at 24px so they're readable over the meadow.
const PROMPT: f32 = 24;

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

    // Center: buy quantity. Click (or Tab / LB / RB) cycles x1/x10/x25.
    const center = rl.Rectangle.init(ox + SLOT + GAP, oy + SLOT + GAP, SLOT, SLOT);
    const hovered = rl.checkCollisionPointRec(mouse, center);
    if (hovered) {
        rl.drawRectangleRounded(center, 0.35, 6, withAlpha(C.surface1, 130));
    }
    const qtyLabel = rl.textFormat("x%d", .{buyQty()});
    const qw = text.measure(qtyLabel, 22);
    text.drawOutline(qtyLabel, @as(i32, @intFromFloat(center.x + SLOT / 2)) - @divFloor(qw, 2), @intFromFloat(center.y + SLOT / 2 - 20), 22, C.yellow, OUTLINE);
    if (input.gamepadActive()) {
        prompt_icons.draw(.pad_lb, center.x + SLOT / 2 - PROMPT - 1, center.y + SLOT / 2 + 4, PROMPT);
        prompt_icons.draw(.pad_rb, center.x + SLOT / 2 + 1, center.y + SLOT / 2 + 4, PROMPT);
    } else {
        const hw = text.measure("Tab", 14);
        text.drawOutline("Tab", @as(i32, @intFromFloat(center.x + SLOT / 2)) - @divFloor(hw, 2), @intFromFloat(center.y + SLOT / 2 + 6), 14, C.subtext0, OUTLINE);
    }
    if (hovered and input.confirmPressed()) cycleBuyQty(1);
}

fn drawBeeSlot(ctx: Context, spec: SlotSpec, pos: rl.Vector2, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(pos.x, pos.y, SLOT, SLOT);
    const cx = rect.x + SLOT / 2;
    const cy = rect.y + SLOT / 2;

    // Soft grounding disc instead of a solid card, so the icons read big and
    // the meadow shows through.
    rl.drawCircleV(rl.Vector2.init(cx, cy), SLOT / 2 - 2, rl.Color.init(17, 17, 27, 110));

    if (!spec.unlocked) {
        // Locked: dark bee silhouette keeps the cross shape and teases the
        // upcoming type.
        rl.drawTexturePro(
            ctx.textures.bee,
            rl.Rectangle.init(0, 0, 32, 32),
            rl.Rectangle.init(cx - 19, cy - 19, 38, 38),
            rl.Vector2.init(0, 0),
            0,
            rl.Color.init(30, 30, 46, 200),
        );
        return;
    }

    const shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
    const qty: u32 = if (shift) @max(buyQty(), 10) else buyQty();
    const totalCost = spec.cost * @as(f32, @floatFromInt(qty));
    const afford = ctx.resources.honey >= totalCost;
    const hovered = rl.checkCollisionPointRec(mouse, rect);
    const pressed = hovered and afford and input.confirmDown();

    if (hovered and afford) {
        rl.drawRing(rl.Vector2.init(cx, cy), SLOT / 2 - 4, SLOT / 2 - 1, 0, 360, 32, C.yellow);
    }

    // Bee sprite, tinted with the type accent (dim when unaffordable).
    const iconSize: f32 = if (pressed) 40 else 44;
    const tint = if (afford) spec.accent else rl.Color.init(spec.accent.r, spec.accent.g, spec.accent.b, 110);
    rl.drawTexturePro(
        ctx.textures.bee,
        rl.Rectangle.init(0, 0, 32, 32),
        rl.Rectangle.init(cx - iconSize / 2, cy - iconSize / 2 - 3, iconSize, iconSize),
        rl.Vector2.init(0, 0),
        0,
        tint,
    );

    // Cost along the slot's bottom edge.
    var cbuf: [32]u8 = undefined;
    const cstr = format.formatShort(totalCost, &cbuf);
    const costLabel = rl.textFormat("%s", .{cstr.ptr});
    const cw = text.measure(costLabel, 14);
    text.drawOutline(costLabel, @as(i32, @intFromFloat(cx)) - @divFloor(cw, 2), @intFromFloat(rect.y + SLOT - 16), 14, if (afford) C.yellow else C.overlay0, OUTLINE);

    // Owned count, top-right.
    const owned = ctx.beeTypeCounts[spec.beeIndex];
    if (owned > 0) {
        const ownedLabel = rl.textFormat("%d", .{owned});
        const ow = text.measure(ownedLabel, 13);
        text.drawOutline(ownedLabel, @as(i32, @intFromFloat(rect.x + SLOT - 2)) - ow, @intFromFloat(rect.y), 13, withAlpha(spec.accent, 230), OUTLINE);
    }

    // Input prompt, top-left corner: d-pad direction or number key.
    const prompt: prompt_icons.Icon = if (input.gamepadActive()) spec.dpad else prompt_icons.numberKey(spec.beeIndex);
    prompt_icons.draw(prompt, rect.x - 3, rect.y - 3, PROMPT);

    if (hovered and afford and input.confirmPressed()) {
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
    const cyf = rect.y + size / 2;

    rl.drawCircleV(rl.Vector2.init(cxf, cyf), size / 2 - 2, rl.Color.init(17, 17, 27, 110));
    if (hovered) {
        rl.drawRing(rl.Vector2.init(cxf, cyf), size / 2 - 4, size / 2 - 1, 0, 360, 32, C.pink);
    }

    // The tree card's sparkle, centered.
    const cx = @as(i32, @intFromFloat(cxf));
    const cy = @as(i32, @intFromFloat(cyf - 6));
    rl.drawCircle(cx, cy, 9, C.mauve);
    rl.drawCircle(cx - 13, cy - 10, 3, C.pink);
    rl.drawCircle(cx + 13, cy + 10, 3, C.pink);
    const label = locale.tr("Tree", "Árvore");
    const lw = text.measure(label, 14);
    text.drawOutline(label, cx - @divFloor(lw, 2), @intFromFloat(rect.y + size - 20), 14, C.subtext0, OUTLINE);

    prompt_icons.draw(if (input.gamepadActive()) .pad_y else .key_t, rect.x - 3, rect.y - 3, PROMPT);

    if (hovered and input.confirmPressed()) out.* = .open_tree;
}

fn drawPassives(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const x: f32 = 12;
    const w: f32 = 235;
    const h: f32 = 34;
    var y: f32 = 64;

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
        const label = rl.textFormat(locale.tr("Prestige  RJ %d · x%.2f", "Prestígio  GR %d · x%.2f"), .{ ctx.prestige.royalJelly, ctx.prestige.globalMul() });
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
