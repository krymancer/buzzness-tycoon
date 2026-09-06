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
    open_storage,
    open_prestige,
    open_discoveries,
    buy: struct { action: actions.BuyAction, qty: u32 },
};

/// Bee buy quantity, cycled by the cross's center button or LB/RB (persists
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
/// readable on the cross's center button.
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

/// Queen's Count: burst on a slot when its type just crossed a milestone.
const MILESTONE_FLASH_TIME: f32 = 0.9;
var milestoneFlash: [4]f32 = @splat(0);

pub fn flashMilestone(index: usize) void {
    if (index < milestoneFlash.len) milestoneFlash[index] = MILESTONE_FLASH_TIME;
}

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
    for (&milestoneFlash) |*f| f.* = @max(0, f.* - dt);
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
        .{ .beeIndex = 0, .buyAction = .buy_worker_bee, .cost = spawners.BEE_TYPE_COSTS.get(.worker), .accent = C.text, .dpad = .dpad_up, .unlocked = true },
        .{ .beeIndex = 1, .buyAction = .buy_swift_bee, .cost = spawners.BEE_TYPE_COSTS.get(.swift), .accent = C.blue, .dpad = .dpad_left, .unlocked = ctx.treeState.hasEffect(.bee_unlock_swift) },
        .{ .beeIndex = 2, .buyAction = .buy_efficient_bee, .cost = spawners.BEE_TYPE_COSTS.get(.efficient), .accent = C.green, .dpad = .dpad_right, .unlocked = ctx.treeState.hasEffect(.bee_unlock_efficient) },
        .{ .beeIndex = 3, .buyAction = .buy_gardener_bee, .cost = spawners.BEE_TYPE_COSTS.get(.gardener), .accent = C.pink, .dpad = .dpad_down, .unlocked = ctx.treeState.hasEffect(.bee_unlock_gardener) },
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

    for (specs, positions) |spec, pos| {
        if (rl.checkCollisionPointRec(mouse, rl.Rectangle.init(pos.x, pos.y, SLOT, SLOT))) drawBeeDetails(ctx, spec, ox, oy - 150, out);
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
    // The label shrinks until it fits the center slot, so x100/x1000 never
    // spill over the bee slots on either side.
    var qbuf: [16]u8 = undefined;
    const qtyText = qtyLabel(buyQty(), &qbuf);
    const maxLabelW: i32 = @intFromFloat(SLOT + 4);
    var qtySize: i32 = 42;
    var qw = text.measure(qtyText, qtySize);
    while (qw > maxLabelW and qtySize > 22) {
        qtySize -= 2;
        qw = text.measure(qtyText, qtySize);
    }
    // Keep the number's optical center where the 42px version sat.
    const numY = ccy - 15 - @as(f32, @floatFromInt(qtySize)) / 2;
    text.drawOutline(qtyText, @as(i32, @intFromFloat(ccx)) - @divFloor(qw, 2), @intFromFloat(numY), qtySize, if (hovered) C.peach else C.yellow, OUTLINE);
    const iconY = ccy - 2;
    if (input.gamepadActive()) {
        prompt_icons.draw(.pad_lb, ccx - PROMPT - 1, iconY, PROMPT);
        prompt_icons.draw(.pad_rb, ccx + 1, iconY, PROMPT);
    } else {
        // The 32x16 TAB tile in a 2x box renders 64x32, centered on the slot.
        prompt_icons.draw(.key_tab, ccx - PROMPT / 2, iconY, PROMPT);
    }
    if (ctx.inputEnabled and hovered and input.confirmPressed()) {
        input.consumeConfirm();
        cycleBuyQty(1);
    }
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

    // Queen's Count: "owned/next milestone" in the top-right corner, and a
    // ring + "x2!" burst when a purchase just crossed one.
    if (bee_ai_system.milestonesUnlocked) {
        const owned: u64 = ctx.beeTypeCounts[spec.beeIndex];
        var mbuf: [48]u8 = undefined;
        const hint = std.fmt.bufPrintZ(&mbuf, "{d}/{d}", .{ owned, bee_ai_system.nextMilestone(owned) }) catch "";
        const hw = text.measure(hint, 12);
        text.drawOutline(hint, @as(i32, @intFromFloat(rect.x + SLOT)) - hw - 2, @intFromFloat(rect.y + 2), 12, C.teal, OUTLINE);
        const mf = milestoneFlash[spec.beeIndex];
        if (mf > 0) {
            const t = 1 - mf / MILESTONE_FLASH_TIME;
            const r = SLOT * (0.5 + 0.6 * t);
            const fade: u8 = @intFromFloat(230 * (1 - t));
            rl.drawRing(rl.Vector2.init(cx, cy), r - 3, r, 0, 360, 32, withAlpha(C.teal, fade));
            var xb: [24]u8 = undefined;
            const mul: u64 = @intFromFloat(bee_ai_system.milestoneMul(owned));
            const label = std.fmt.bufPrintZ(&xb, "x{d}!", .{mul}) catch "";
            const lw = text.measure(label, 20);
            text.drawOutline(label, @as(i32, @intFromFloat(cx)) - @divFloor(lw, 2), @intFromFloat(cy - 14 - 22 * t), 20, withAlpha(C.teal, fade), OUTLINE);
        }
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

    // Not affordable yet: how long until it is, top-right corner (under
    // the Queen's Count hint when that's showing). Turns "can't" into
    // "soon".
    if (!afford) {
        if (ctx.resources.purchaseWait(totalCost)) |secs| {
            var ebuf: [16]u8 = undefined;
            if (format.formatEta(secs, &ebuf)) |eta| {
                const ew = text.measure(eta, 13);
                const ey: f32 = if (bee_ai_system.milestonesUnlocked) 16 else 2;
                text.drawOutline(eta, @as(i32, @intFromFloat(rect.x + SLOT - 2)) - ew, @intFromFloat(rect.y + ey), 13, C.peach, OUTLINE);
            }
        }
    }

    if (ctx.inputEnabled and hovered and afford and input.confirmPressed()) {
        input.consumeConfirm();
        flashSlot(spec.beeIndex);
        out.* = .{ .buy = .{ .action = spec.buyAction, .qty = qty } };
    }
}

var lastAffordable: usize = 0;
var affordableFlash: f32 = 0;

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

    // "N upgrades affordable" badge, top-right, pulsing: the player never
    // has to open the tree to find out something is buyable.
    const affordable = ctx.treeState.affordableCount(ctx.resources.honey, ctx.prestigeCostMul, ctx.ascensions);
    if (affordable > lastAffordable) affordableFlash = 1;
    lastAffordable = affordable;
    affordableFlash = @max(0, affordableFlash - rl.getFrameTime());
    if (affordable > 0) {
        const t: f32 = @floatCast(rl.getTime());
        const pulse = affordableFlash * (0.5 + 0.5 * @sin(t * 4.0));
        const bx = rect.x + size - 4;
        const by = rect.y + 4;
        const r: f32 = 11 + 1.5 * pulse;
        rl.drawCircleV(rl.Vector2.init(bx, by), r + 5, rl.Color.init(C.yellow.r, C.yellow.g, C.yellow.b, @intFromFloat(40 + 50 * pulse)));
        rl.drawCircleV(rl.Vector2.init(bx, by), r + 2, OUTLINE);
        rl.drawCircleV(rl.Vector2.init(bx, by), r, C.yellow);
        const label = if (affordable > 9) "9+" else rl.textFormat("%d", .{@as(c_int, @intCast(affordable))});
        const lw = text.measure(label, 15);
        text.draw(label, @as(i32, @intFromFloat(bx)) - @divFloor(lw, 2), @as(i32, @intFromFloat(by)) - 9, 15, C.base);
    }

    if (ctx.inputEnabled and hovered and input.confirmPressed()) {
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
/// dark silhouette (same treatment as the cross). Cells are laid out
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
        text.draw(locale.tr("Increase storage · open tree [T/Y]", "Aumente o armazém · árvore [T/Y]"), ix, iy + 100, 15, C.peach);
        // Clicking a blocked slot takes the player to the actual prerequisite.
        if (ctx.inputEnabled and input.confirmPressed()) {
            input.consumeConfirm();
            out.* = .open_storage;
        }
    } else if (ctx.resources.purchaseWait(cost)) |secs| {
        if (secs > 0) {
            var b: [16]u8 = undefined;
            if (format.formatEta(secs, &b)) |eta| text.draw(rl.textFormat(locale.tr("About %s at current production", "Cerca de %s na produção atual"), .{eta.ptr}), ix, iy + 100, 15, C.peach);
        }
    }
}
