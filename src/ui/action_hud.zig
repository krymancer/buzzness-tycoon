//! Overlay action HUD that replaced the shop side panel: the meadow gets the
//! full window, and the controls float over it, cursor-first.
//!
//! - Bottom-left: boxed vertical bee purchases. Each
//!   row preserves its d-pad direction; the quantity button shows and
//!   cycles the buy quantity (x1/x10/x25, also LB/RB).
//! - Below the bees: boxed upgrade-tree button (Y / T).
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
const bee_ai_system = @import("../ecs/systems/bee_ai_system.zig");
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
    /// stats.prestigeCount and PrestigeState.costMul(): what the tree needs
    /// to price nodes, for the tree button's "N affordable" badge.
    ascensions: u32,
    prestigeCostMul: f32,
    /// Unlocked / total achievements, for the Discoveries row.
    discoveries: usize,
    discoveriesTotal: usize,
    // False while a modal (tree, pause, prestige) covers the HUD: it still
    // draws underneath, but must not react to clicks aimed at the modal —
    // the tree's Close button sits on the same corner as the tree button.
    inputEnabled: bool = true,
};

pub const Action = union(enum) {
    none,
    open_tree,
    buy_storage,
    open_prestige,
    open_discoveries,
    buy: struct { action: actions.BuyAction, qty: u32 },
};

/// Bee buy quantity, cycled by the quantity button or LB/RB (persists
/// for the session). Holding Shift while buying still bulk-buys x10+.
/// The x50/x100/x500/x1000 steps unlock via the Bulk Order tree node, one
/// per level; the Royal Shop's Wholesale Contract adds one more step per
/// level on top of that (x5000 ... x100000 with both maxed), and being a
/// prestige perk it survives every run.
pub const BUY_QTYS = [_]u32{ 1, 10, 25, 50, 100, 500, 1000, 5000, 10000, 50000, 100000 };
pub const BASE_QTY_COUNT: usize = 3;
/// Steps reachable from the tree alone (base + Bulk Order levels).
pub const TREE_QTY_COUNT: usize = 7;
var treeTier: u16 = 0;
var shopTier: u16 = 0;
var unlockedQtyCount: usize = BASE_QTY_COUNT;
var buyQtyIndex: usize = 0;

/// Sync the unlocked quantity steps with the Bulk Order node level
/// (purchase, load, and run reset all funnel through here).
pub fn setBulkTier(level: u16) void {
    treeTier = level;
    refreshUnlocked();
}

/// Sync with the Wholesale Contract shop level (purchase, load, run start).
pub fn setShopTier(level: u16) void {
    shopTier = level;
    refreshUnlocked();
}

fn refreshUnlocked() void {
    unlockedQtyCount = unlockedCountFor(treeTier, shopTier);
    if (buyQtyIndex >= unlockedQtyCount) buyQtyIndex = 0;
}

fn unlockedCountFor(tree: u16, shop: u16) usize {
    return @min(BUY_QTYS.len, BASE_QTY_COUNT + @as(usize, tree) + @as(usize, shop));
}

/// Largest quantity step available at the current tree level with `shop`
/// Wholesale Contract levels (the shop's "Now / Next" line).
pub fn topQtyWithShopLevel(shop: u16) u32 {
    return BUY_QTYS[unlockedCountFor(treeTier, shop) - 1];
}

/// Quantity label: "x1000", "x10K", "x100K" — keeps the biggest steps
/// readable on the quantity button.
pub fn qtyLabel(qty: u32, buf: []u8) [:0]const u8 {
    if (qty >= 10_000) return std.fmt.bufPrintZ(buf, "x{d}K", .{qty / 1000}) catch "x?";
    return std.fmt.bufPrintZ(buf, "x{d}", .{qty}) catch "x?";
}

test "quantity steps: tree and shop levels stack, capped at the table" {
    try std.testing.expectEqual(@as(usize, 3), unlockedCountFor(0, 0));
    try std.testing.expectEqual(@as(usize, 7), unlockedCountFor(4, 0));
    try std.testing.expectEqual(@as(usize, 7), unlockedCountFor(0, 4));
    try std.testing.expectEqual(BUY_QTYS.len, unlockedCountFor(4, 4));
    try std.testing.expectEqual(BUY_QTYS.len, unlockedCountFor(9, 9));
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("x1000", qtyLabel(1000, &buf));
    try std.testing.expectEqualStrings("x5000", qtyLabel(5000, &buf));
    try std.testing.expectEqualStrings("x100K", qtyLabel(100000, &buf));
}

pub fn buyQty() u32 {
    return BUY_QTYS[buyQtyIndex];
}

/// Quantity a purchase should use right now: the selected qty, with Shift
/// held forcing at least x10. Shared by the bee rows and the d-pad /
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
/// Prompt icons draw at 32px (2x the 16px tiles) — crisp and readable.
const PROMPT: f32 = 32;
/// Successful-buy glow duration per slot.
const FLASH_TIME: f32 = 0.3;

var slotFlash: [4]f32 = @splat(0);

/// Queen's Count: burst on a slot when its type just crossed a milestone.
const MILESTONE_FLASH_TIME: f32 = 0.9;
var milestoneFlash: [4]f32 = @splat(0);

pub fn flashMilestone(index: usize) void {
    if (index < milestoneFlash.len) milestoneFlash[index] = MILESTONE_FLASH_TIME;
}

/// Trigger the buy glow on a bee row (0 worker, 1 swift, 2 efficient,
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
    for (&milestoneFlash) |*f| f.* = @max(0, f.* - dt);
    drawBeeColumn(ctx, mouse, &action);
    drawTreeButton(ctx, mouse, &action);
    drawPassives(ctx, mouse, &action);
    return action;
}

fn drawBeeColumn(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const ox = MARGIN;
    const oy = ctx.screenHeight - MARGIN - 382;
    const panel = rl.Rectangle.init(ox, oy, 228, 320);
    input.registerBlock(panel);
    rl.drawRectangleRounded(panel, 0.08, 6, withAlpha(C.mantle, 235));
    rl.drawRectangleRoundedLinesEx(panel, 0.08, 6, 1, C.surface1);
    text.draw(locale.tr("Buy bees", "Comprar abelhas"), @intFromFloat(ox + 12), @intFromFloat(oy + 12), 22, C.yellow);

    const specs = [_]SlotSpec{
        .{ .beeIndex = 0, .buyAction = .buy_worker_bee, .cost = spawners.BEE_TYPE_COSTS.get(.worker), .accent = C.text, .dpad = .dpad_up, .unlocked = true },
        .{ .beeIndex = 1, .buyAction = .buy_swift_bee, .cost = spawners.BEE_TYPE_COSTS.get(.swift), .accent = C.blue, .dpad = .dpad_left, .unlocked = ctx.treeState.hasEffect(.bee_unlock_swift) },
        .{ .beeIndex = 2, .buyAction = .buy_efficient_bee, .cost = spawners.BEE_TYPE_COSTS.get(.efficient), .accent = C.green, .dpad = .dpad_right, .unlocked = ctx.treeState.hasEffect(.bee_unlock_efficient) },
        .{ .beeIndex = 3, .buyAction = .buy_gardener_bee, .cost = spawners.BEE_TYPE_COSTS.get(.gardener), .accent = C.pink, .dpad = .dpad_down, .unlocked = ctx.treeState.hasEffect(.bee_unlock_gardener) },
    };
    const names = [_][:0]const u8{ locale.tr("Worker", "Operária"), locale.tr("Swift", "Veloz"), locale.tr("Efficient", "Eficiente"), locale.tr("Gardener", "Jardineira") };
    var hoveredSpec: ?SlotSpec = null;
    for (specs, 0..) |spec, i| {
        const rect = rl.Rectangle.init(ox + 8, oy + 44 + @as(f32, @floatFromInt(i)) * 56, 212, 50);
        input.registerHotspot(rect);
        const hovered = ctx.inputEnabled and rl.checkCollisionPointRec(mouse, rect);
        const qty = effectiveBuyQty();
        const cost = spec.cost * @as(f32, @floatFromInt(qty));
        const afford = spec.unlocked and ctx.resources.honey >= cost;
        rl.drawRectangleRounded(rect, 0.12, 6, if (hovered) C.surface1 else C.surface0);
        if (slotFlash[i] > 0 or milestoneFlash[i] > 0) rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, 2, C.yellow);
        rl.drawTexturePro(ctx.textures.bee, rl.Rectangle.init(0, 0, 32, 32), rl.Rectangle.init(rect.x + 2, rect.y + 2, 46, 46), rl.Vector2.init(0, 0), 0, if (spec.unlocked) spec.accent else C.overlay0);
        text.draw(names[i], @intFromFloat(rect.x + 48), @intFromFloat(rect.y + 6), 18, if (spec.unlocked) spec.accent else C.overlay0);
        var cb: [32]u8 = undefined;
        const label = if (!spec.unlocked) locale.tr("Locked", "Bloqueado") else rl.textFormat("%s", .{format.formatShort(cost, &cb).ptr});
        icons.drawHoneyDrop(rect.x + 53, rect.y + 37, 4, if (afford) C.yellow else C.overlay0);
        text.draw(label, @intFromFloat(rect.x + 62), @intFromFloat(rect.y + 28), 16, if (afford) C.yellow else C.subtext0);
        prompt_icons.draw(if (input.gamepadActive()) spec.dpad else prompt_icons.numberKey(i), rect.x + rect.width - 30, rect.y + 8, 24);
        if (hovered) hoveredSpec = spec;
        if (hovered and afford and input.confirmPressed()) {
            input.consumeConfirm();
            flashSlot(i);
            out.* = .{ .buy = .{ .action = spec.buyAction, .qty = qty } };
        }
    }
    const qtyRect = rl.Rectangle.init(ox + 8, oy + 272, 212, 38);
    input.registerHotspot(qtyRect);
    const hovered = ctx.inputEnabled and rl.checkCollisionPointRec(mouse, qtyRect);
    rl.drawRectangleRounded(qtyRect, 0.16, 6, if (hovered) C.surface1 else C.base);
    var qbuf: [16]u8 = undefined;
    text.draw(qtyLabel(buyQty(), &qbuf), @intFromFloat(qtyRect.x + 12), @intFromFloat(qtyRect.y + 9), 20, C.yellow);
    if (input.gamepadActive()) {
        prompt_icons.draw(.pad_lb, qtyRect.x + 150, qtyRect.y + 6, 24);
        prompt_icons.draw(.pad_rb, qtyRect.x + 180, qtyRect.y + 6, 24);
    } else prompt_icons.draw(.key_tab, qtyRect.x + 178, qtyRect.y + 6, 24);
    if (hovered and input.confirmPressed()) {
        input.consumeConfirm();
        cycleBuyQty(1);
    }
    if (hoveredSpec) |spec| drawBeeDetails(ctx, spec, ox + 236, @min(oy + 44, ctx.screenHeight - 154), out);
}

fn drawTreeButton(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(MARGIN, ctx.screenHeight - MARGIN - 52, 228, 52);
    input.registerBlock(rect);
    input.registerHotspot(rect);
    const hovered = ctx.inputEnabled and rl.checkCollisionPointRec(mouse, rect);
    rl.drawRectangleRounded(rect, 0.12, 6, if (hovered) C.surface1 else withAlpha(C.mantle, 235));
    rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, 1, if (hovered) C.mauve else C.surface1);
    prompt_icons.draw(if (input.gamepadActive()) .pad_y else .key_t, rect.x + 8, rect.y + 12, 28);
    text.draw(locale.tr("Tech tree", "Tecnologias"), @intFromFloat(rect.x + 42), @intFromFloat(rect.y + 17), 20, C.mauve);
    const affordable = ctx.treeState.affordableCount(ctx.resources.honey, ctx.prestigeCostMul, ctx.ascensions);
    if (affordable > 0) {
        const badge = rl.Rectangle.init(rect.x + rect.width - 38, rect.y + 14, 30, 24);
        rl.drawRectangleRec(badge, C.yellow);
        const label = rl.textFormat("%d", .{@as(c_int, @intCast(affordable))});
        text.draw(label, @intFromFloat(badge.x + (30 - @as(f32, @floatFromInt(text.measure(label, 16)))) / 2), @intFromFloat(badge.y + 4), 16, C.crust);
    }
    if (hovered and input.confirmPressed()) {
        input.consumeConfirm();
        out.* = .open_tree;
    }
}

const CENSUS_ICON: f32 = 30;
const CENSUS_GAP: f32 = 8;
const CENSUS_FONT: i32 = 16;
/// Narrowest the status column gets; it widens to fit the bee counts.
const PASSIVE_MIN_W: f32 = 250;

fn censusLabel(ctx: Context, i: usize, buf: []u8) [:0]const u8 {
    var nbuf: [32]u8 = undefined;
    const nstr = format.formatShort(@floatFromInt(ctx.beeTypeCounts[i]), &nbuf);
    return std.fmt.bufPrintZ(buf, "x{s}", .{nstr}) catch "x?";
}

/// Width the census row needs so every count fits; the whole status column
/// follows it, since counts like x20.46K outgrow a fixed box.
fn censusWidth(ctx: Context) f32 {
    var total: f32 = 6;
    for (0..4) |i| {
        var lbuf: [40]u8 = undefined;
        const label = censusLabel(ctx, i, &lbuf);
        total += CENSUS_ICON - 1 + @as(f32, @floatFromInt(text.measure(label, CENSUS_FONT))) + CENSUS_GAP;
    }
    return @max(PASSIVE_MIN_W, total);
}

/// Bee census row: one icon + owned count per type; locked types show the
/// dark silhouette (same treatment as the purchase rows). Cells are laid out
/// left-to-right by content width, then the whole set is centered in the row.
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
    var labelBufs: [4][40]u8 = undefined;
    var labels: [4][:0]const u8 = undefined;
    var cellW: [4]f32 = undefined;
    var total: f32 = 0;
    for (0..4) |i| {
        labels[i] = censusLabel(ctx, i, &labelBufs[i]);
        cellW[i] = CENSUS_ICON - 1 + @as(f32, @floatFromInt(text.measure(labels[i], CENSUS_FONT))) + CENSUS_GAP;
        total += cellW[i];
    }
    var cx = x + @max(2, (w - total) / 2);
    for (accents, unlocked, 0..) |accent, isUnlocked, i| {
        const tint = if (isUnlocked) accent else rl.Color.init(30, 30, 46, 200);
        rl.drawTexturePro(
            ctx.textures.bee,
            rl.Rectangle.init(0, 0, 32, 32),
            rl.Rectangle.init(cx, y + (h - CENSUS_ICON) / 2, CENSUS_ICON, CENSUS_ICON),
            rl.Vector2.init(0, 0),
            0,
            tint,
        );
        text.draw(labels[i], @intFromFloat(cx + CENSUS_ICON - 3), @intFromFloat(y + (h - 16) / 2), CENSUS_FONT, if (isUnlocked) C.text else C.overlay0);
        cx += cellW[i];
    }
}

fn drawPassives(ctx: Context, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const w: f32 = censusWidth(ctx);
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
        // Multiplier and reach; no fill meter — it never moved and read as
        // a cooldown that was stuck full.
        const label = rl.textFormat("Aura x%.2f · %.0f %s", .{ ctx.labs.auraMul, ctx.labs.auraReach, locale.tr("tiles", "células").ptr });
        drawPassiveRow(x, y, w, h, .aura, label, true, 0, C.lavender);
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
        // Spendable jelly (what the shop reads) and the short-formatted
        // multiplier, which runs into the millions after a few prestiges.
        var jbuf: [32]u8 = undefined;
        var mbuf: [32]u8 = undefined;
        const jstr = format.formatShort(@floatFromInt(ctx.prestige.availableJelly()), &jbuf);
        const mul = ctx.prestige.globalMul();
        const mstr = if (mul < 1000.0) (std.fmt.bufPrintZ(&mbuf, "{d:.2}", .{mul}) catch "?") else format.formatShort(mul, &mbuf);
        const label = rl.textFormat(locale.tr("Prestige  RJ %s · x%s", "Prestígio  GR %s · x%s"), .{ jstr.ptr, mstr.ptr });
        text.draw(label, @intFromFloat(x + 32), @intFromFloat(y + 8), 16, if (hovered) C.pink else C.subtext1);
        if (ctx.inputEnabled and hovered and input.confirmPressed()) {
            input.consumeConfirm();
            out.* = .open_prestige;
        }
        y += h + 6;
    }

    // Discoveries: the achievement book (also on B).
    {
        const rect = rl.Rectangle.init(x, y, w, h);
        input.registerBlock(rect);
        input.registerHotspot(rect);
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        rl.drawRectangleRounded(rect, 0.4, 6, withAlpha(if (hovered) C.surface1 else C.surface0, 225));
        rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, if (hovered) 2 else 1, if (hovered) C.yellow else C.surface1);
        // Little book: two pages and a spine.
        const bx = x + 16;
        const by = y + h / 2;
        const page = if (hovered) C.yellow else C.subtext0;
        rl.drawRectangleRounded(rl.Rectangle.init(bx - 8, by - 6, 7, 12), 0.3, 4, page);
        rl.drawRectangleRounded(rl.Rectangle.init(bx + 1, by - 6, 7, 12), 0.3, 4, page);
        rl.drawRectangleRec(rl.Rectangle.init(bx - 1, by - 7, 2, 14), C.mantle);
        const label = rl.textFormat(locale.tr("Discoveries  %d/%d", "Descobertas  %d/%d"), .{ @as(c_int, @intCast(ctx.discoveries)), @as(c_int, @intCast(ctx.discoveriesTotal)) });
        text.draw(label, @intFromFloat(x + 32), @intFromFloat(y + 8), 16, if (hovered) C.yellow else C.subtext1);
        if (ctx.inputEnabled and hovered and input.confirmPressed()) {
            input.consumeConfirm();
            out.* = .open_discoveries;
        }
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

/// Outline color for HUD text floating over the meadow.
const OUTLINE = @import("hud.zig").OUTLINE;

fn drawBeeDetails(ctx: Context, spec: SlotSpec, x: f32, y: f32, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const names = [_][:0]const u8{ locale.tr("Worker", "Operária"), locale.tr("Swift", "Veloz"), locale.tr("Efficient", "Eficiente"), locale.tr("Gardener", "Jardineira") };
    const roles = [_][:0]const u8{ locale.tr("Collects pollen", "Coleta pólen"), locale.tr("Flies twice as fast", "Voa duas vezes mais rápido"), locale.tr("Collects twice as fast", "Coleta duas vezes mais rápido"), locale.tr("Collects and plants flowers", "Coleta e planta flores") };
    const rect = rl.Rectangle.init(x, @max(110, y), 290, 138);
    input.registerBlock(rect);
    rl.drawRectangleRounded(rect, 0.12, 6, withAlpha(C.mantle, 245));
    rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, 1, spec.accent);
    const ix: i32 = @intFromFloat(rect.x + 12);
    const iy: i32 = @intFromFloat(rect.y + 10);
    text.draw(names[spec.beeIndex], ix, iy, 22, spec.accent);
    text.draw(roles[spec.beeIndex], ix, iy + 26, 16, C.subtext1);
    if (!spec.unlocked) {
        text.draw(locale.tr("Unlock in the Upgrade Tree", "Desbloqueie na árvore"), ix, iy + 55, 16, C.peach);
        return;
    }
    const cost = spec.cost * @as(f32, @floatFromInt(effectiveBuyQty()));
    var costBuf: [32]u8 = undefined;
    const costText = format.formatShort(cost, &costBuf);
    text.draw(rl.textFormat(locale.tr("Buy x%d · %s honey", "Comprar x%d · %s mel"), .{ @as(c_int, @intCast(effectiveBuyQty())), costText.ptr }), ix, iy + 49, 17, C.yellow);
    var ownedBuf: [32]u8 = undefined;
    var nextBuf: [32]u8 = undefined;
    const owned = ctx.beeTypeCounts[spec.beeIndex];
    const own = format.formatShort(@floatFromInt(owned), &ownedBuf);
    const next = format.formatShort(@floatFromInt(bee_ai_system.nextMilestone(owned)), &nextBuf);
    const label = if (bee_ai_system.milestonesUnlocked)
        rl.textFormat(locale.tr("Owned %s · next milestone %s", "Possui %s · próxima meta %s"), .{ own.ptr, next.ptr })
    else
        rl.textFormat(locale.tr("Owned %s", "Possui %s"), .{own.ptr});
    text.draw(label, ix, iy + 72, 15, C.subtext0);
    if (ctx.resources.needsStorage(cost)) {
        const storage = upgrade_tree.findNode(upgrade_tree.STORAGE_ID).?;
        var sb: [32]u8 = undefined;
        const storageCost = ctx.treeState.nextCost(storage, ctx.prestigeCostMul);
        text.draw(rl.textFormat(locale.tr("Click: storage + · %s honey", "Clique: armazém + · %s mel"), .{format.formatShort(storageCost, &sb).ptr}), ix, iy + 100, 15, C.peach);
        // Upgrade capacity without leaving the meadow.
        if (ctx.inputEnabled and input.confirmPressed()) {
            input.consumeConfirm();
            out.* = .buy_storage;
        }
    } else if (ctx.resources.purchaseWait(cost)) |secs| {
        if (secs > 0) {
            var b: [16]u8 = undefined;
            if (format.formatEta(secs, &b)) |eta| text.draw(rl.textFormat(locale.tr("About %s at current production", "Cerca de %s na produção atual"), .{eta.ptr}), ix, iy + 100, 15, C.peach);
        }
    }
}
