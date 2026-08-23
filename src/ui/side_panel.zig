const rl = @import("raylib");
const text = @import("../text.zig");
const rg = @import("raygui");
const std = @import("std");

const theme = @import("../theme.zig");
const format = @import("../format.zig");
const Resources = @import("../resources.zig").Resources;
const spawners = @import("../spawners.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const prestige_mod = @import("../prestige.zig");
const labs_mod = @import("../labs.zig");
const Textures = @import("../textures.zig").Textures;
const popups = @import("popups.zig");
const locale = @import("../localization.zig");
const icons = @import("icons.zig");

pub const PANEL_WIDTH: f32 = 360;

pub const SidePanelContext = struct {
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

pub const SidePanelAction = union(enum) {
    none,
    open_tree,
    open_prestige,
    buy: struct { action: popups.TilePopupAction, qty: u32 },
};

/// Bee buy quantity, toggled by the chips in the Bees header (persists for
/// the session). Holding Shift while clicking a card buys x10 regardless.
pub const BUY_QTYS = [_]u32{ 1, 10, 25 };
var buyQtyIndex: usize = 0;

pub fn buyQty() u32 {
    return BUY_QTYS[buyQtyIndex];
}

pub fn isMouseInPanel(mousePos: rl.Vector2, screenWidth: f32) bool {
    return mousePos.x >= screenWidth - PANEL_WIDTH;
}

pub fn draw(ctx: SidePanelContext) SidePanelAction {
    const C = theme.CatppuccinMocha.Color;
    const panelX = ctx.screenWidth - PANEL_WIDTH;

    // Panel bg + left accent
    rl.drawRectangle(@intFromFloat(panelX), 0, @intFromFloat(PANEL_WIDTH), @intFromFloat(ctx.screenHeight), C.mantle);
    rl.drawRectangle(@intFromFloat(panelX), 0, 3, @intFromFloat(ctx.screenHeight), C.yellow);

    // Title with buzzy flourish
    const titleText = locale.tr("Buzz Shop", "Loja da Colmeia");
    const titleW = text.measure(titleText, 30);
    const titleX = @as(i32, @intFromFloat(panelX + PANEL_WIDTH / 2)) - @divFloor(titleW, 2);
    text.draw(titleText, titleX, 12, 30, C.yellow);
    // honeycomb dots under title
    const dotsY: i32 = 44;
    const dotCenterX = @as(i32, @intFromFloat(panelX + PANEL_WIDTH / 2));
    rl.drawCircle(dotCenterX - 18, dotsY, 3, C.peach);
    rl.drawCircle(dotCenterX, dotsY, 4, C.yellow);
    rl.drawCircle(dotCenterX + 18, dotsY, 3, C.peach);

    const contentX = panelX + 14;
    const contentW: f32 = PANEL_WIDTH - 28;
    var y: f32 = 62;

    var action: SidePanelAction = .none;
    const mouse = rl.getMousePosition();

    // Upgrade Tree card (mauve-accent)
    y = drawTreeCard(contentX, y, contentW, mouse, &action);

    // Bees section, with the x1/x10/x25 quantity chips on the header row.
    drawQtyChips(contentX + contentW, y - 2, mouse);
    y = drawSectionHeader(contentX, y, contentW, locale.tr("Bees", "Abelhas"), C.yellow);
    const honey = ctx.resources.honey;

    y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Worker", "Operária"), locale.tr("+pollen", "+pólen"), spawners.BEE_TYPE_COSTS.worker, C.text, ctx.beeTypeCounts[0], &action, .buy_worker_bee, honey);
    if (ctx.treeState.hasEffect(.bee_unlock_swift)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Swift", "Veloz"), locale.tr("2x speed", "velocidade 2x"), spawners.BEE_TYPE_COSTS.swift, C.blue, ctx.beeTypeCounts[1], &action, .buy_swift_bee, honey);
    }
    if (ctx.treeState.hasEffect(.bee_unlock_efficient)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Efficient", "Eficiente"), locale.tr("2x pollen", "pólen 2x"), spawners.BEE_TYPE_COSTS.efficient, C.green, ctx.beeTypeCounts[2], &action, .buy_efficient_bee, honey);
    }
    if (ctx.treeState.hasEffect(.bee_unlock_gardener)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Gardener", "Jardineira"), locale.tr("plants flowers", "planta flores"), spawners.BEE_TYPE_COSTS.gardener, C.pink, ctx.beeTypeCounts[3], &action, .buy_gardener_bee, honey);
    }

    // Prestige section
    if (ctx.prestige.hasUnlockedPrestige) {
        y = drawSectionHeader(contentX, y, contentW, locale.tr("Royal Jelly", "Geleia Real"), C.mauve);
        y = drawPrestigeCard(contentX, y, contentW, mouse, ctx.prestige, &action);
    }

    drawFooter(ctx, panelX, mouse);

    return action;
}

const FOOTER_H: f32 = 44;
const FOOTER_GAP: f32 = 8;

const MeterIcon = enum { sprout, aura };

/// Bottom-anchored status stack (grows upward): Instant Grow, then Aura as
/// they unlock. Every row is "[icon] Name: state".
fn drawFooter(ctx: SidePanelContext, panelX: f32, mouse: rl.Vector2) void {
    const C = theme.CatppuccinMocha.Color;
    const x = panelX + 14;
    const w = PANEL_WIDTH - 28;
    var y = ctx.screenHeight - FOOTER_H - 10;

    if (ctx.treeState.hasEffect(.growth_boost_unlock)) {
        const ready = ctx.resources.canUseGrowthBoost();
        const label = if (ready)
            locale.tr("Instant Grow: ready", "Crescer instantâneo: pronto")
        else
            rl.textFormat(locale.tr("Instant Grow: %.1fs", "Crescer instantâneo: %.1fs"), .{ctx.resources.growthBoostCooldown});
        const fill = 1.0 - ctx.resources.getCooldownPercent();
        _ = drawMeter(.{ .x = x, .y = y, .w = w, .icon = .sprout, .label = label, .ready = ready, .fill = fill, .accent = C.green, .mouse = mouse });
        y -= FOOTER_H + FOOTER_GAP;
    }

    if (ctx.treeState.hasEffect(.lab_aura)) {
        const label = rl.textFormat("Aura x%.2f", .{ctx.labs.auraMul});
        _ = drawMeter(.{ .x = x, .y = y, .w = w, .icon = .aura, .label = label, .ready = true, .fill = 1.0, .accent = C.lavender, .mouse = mouse });
    }
}

const Meter = struct {
    x: f32,
    y: f32,
    w: f32,
    icon: MeterIcon,
    label: [:0]const u8,
    ready: bool,
    fill: f32,
    accent: rl.Color,
    clickable: bool = false,
    /// Hotkey hint drawn at the right edge (e.g. "B").
    hotkey: ?[:0]const u8 = null,
    mouse: rl.Vector2,
};

/// Rounded status row: proportional fill, "[icon] label" centred as a group,
/// optional hotkey chip. Returns true when clicked (only if clickable+ready).
fn drawMeter(m: Meter) bool {
    const C = theme.CatppuccinMocha.Color;
    const h = FOOTER_H;
    const rect = rl.Rectangle.init(m.x, m.y, m.w, h);
    const hovered = m.clickable and m.ready and rl.checkCollisionPointRec(m.mouse, rect);

    rl.drawRectangleRounded(rect, 0.4, 6, if (hovered) C.surface1 else C.surface0);

    const fillW = (m.w - 6) * std.math.clamp(m.fill, 0, 1);
    if (fillW > 1) {
        const fillColor = if (m.ready) rl.Color.init(m.accent.r, m.accent.g, m.accent.b, 60) else rl.Color.init(88, 91, 112, 70);
        rl.drawRectangleRounded(rl.Rectangle.init(m.x + 3, m.y + 3, fillW, h - 6), 0.4, 6, fillColor);
    }
    rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, if (hovered) 2 else 1, if (m.ready) m.accent else C.surface1);

    const labelSize: i32 = 18;
    const iconH: f32 = 19;
    const iconW: f32 = iconH * 1.1;
    const gap: f32 = 7;
    const tw: f32 = @floatFromInt(text.measure(m.label, labelSize));
    const groupW = iconW + gap + tw;
    const startX = m.x + (m.w - groupW) / 2;
    const iconCx = startX + iconW / 2;
    const midY = m.y + h / 2;
    const iconColor = if (m.ready) m.accent else C.overlay1;
    switch (m.icon) {
        .sprout => icons.drawSprout(iconCx, midY + iconH / 2 - 1, iconH, iconColor),
        .aura => icons.drawAura(iconCx, midY, iconH / 2, iconColor),
    }
    const ty = m.y + (h - @as(f32, @floatFromInt(labelSize))) / 2;
    text.draw(m.label, @intFromFloat(startX + iconW + gap), @intFromFloat(ty), labelSize, if (m.ready) m.accent else C.subtext1);

    if (m.hotkey) |key| {
        const chip: f32 = 20;
        const kx = m.x + m.w - chip - 8;
        const ky = midY - chip / 2;
        rl.drawRectangleRounded(rl.Rectangle.init(kx, ky, chip, chip), 0.3, 4, C.surface2);
        const kw = text.measure(key, 13);
        text.draw(key, @as(i32, @intFromFloat(kx + chip / 2)) - @divFloor(kw, 2), @intFromFloat(ky + 3), 13, C.subtext0);
    }

    return hovered and rl.isMouseButtonPressed(rl.MouseButton.left);
}

fn drawSectionHeader(x: f32, y: f32, w: f32, label: [:0]const u8, color: rl.Color) f32 {
    const C = theme.CatppuccinMocha.Color;
    _ = C;
    const lineY = y + 10;
    const textW = text.measure(label, 18);
    const labelX = @as(i32, @intFromFloat(x + w / 2)) - @divFloor(textW, 2);
    // two side lines + centered label
    rl.drawLine(@intFromFloat(x), @intFromFloat(lineY), labelX - 8, @intFromFloat(lineY), color);
    rl.drawLine(labelX + textW + 8, @intFromFloat(lineY), @as(i32, @intFromFloat(x + w)), @intFromFloat(lineY), color);
    text.draw(label, labelX, @as(i32, @intFromFloat(y)), 18, color);
    return y + 32;
}

fn drawTreeCard(x: f32, y: f32, w: f32, mouse: rl.Vector2, out: *SidePanelAction) f32 {
    const C = theme.CatppuccinMocha.Color;
    const h: f32 = 60;
    const rect = rl.Rectangle.init(x, y, w, h);
    const hovered = rl.checkCollisionPointRec(mouse, rect);

    const border = if (hovered) C.mauve else C.surface2;
    rl.drawRectangleRounded(rect, 0.2, 6, C.surface0);
    rl.drawRectangleRoundedLinesEx(rect, 0.2, 6, 2, border);

    // sparkle on the left
    const sparkleX = @as(i32, @intFromFloat(x + 18));
    const sparkleY = @as(i32, @intFromFloat(y + h / 2));
    rl.drawCircle(sparkleX, sparkleY, 6, C.mauve);
    rl.drawCircle(sparkleX - 10, sparkleY - 8, 2, C.pink);
    rl.drawCircle(sparkleX + 10, sparkleY + 8, 2, C.pink);

    text.draw(locale.tr("Upgrade Tree", "Árvore de Melhorias"), sparkleX + 22, @as(i32, @intFromFloat(y + 7)), 20, C.text);
    text.draw(locale.tr("Progression & perks", "Progressão e bônus"), sparkleX + 22, @as(i32, @intFromFloat(y + 34)), 16, C.subtext0);

    if (hovered and rl.isMouseButtonPressed(rl.MouseButton.left)) {
        out.* = .open_tree;
    }

    return y + h + 12;
}

fn drawBeeCard(
    ctx: SidePanelContext,
    x: f32,
    y: f32,
    w: f32,
    mouse: rl.Vector2,
    name: [:0]const u8,
    perk: [:0]const u8,
    cost: f32,
    accent: rl.Color,
    owned: usize,
    out: *SidePanelAction,
    buyAction: popups.TilePopupAction,
    honey: f32,
) f32 {
    const C = theme.CatppuccinMocha.Color;
    const h: f32 = 66;
    const rect = rl.Rectangle.init(x, y, w, h);
    const shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
    const qty: u32 = if (shift) @max(buyQty(), 10) else buyQty();
    const totalCost = cost * @as(f32, @floatFromInt(qty));
    const afford = honey >= totalCost;
    const hovered = rl.checkCollisionPointRec(mouse, rect);

    // Pressed cards sink a couple of pixels and darken, so a click reads as a
    // physical push even before the "-cost" popup confirms it.
    const pressed = hovered and afford and rl.isMouseButtonDown(rl.MouseButton.left);
    const off: f32 = if (pressed) 2 else 0;
    const px = x + off;
    const py = y + off;
    const cardRect = rl.Rectangle.init(px, py, w, h);

    // card bg
    rl.drawRectangleRounded(cardRect, 0.18, 6, if (pressed) C.surface1 else C.surface0);

    // accent strip on left (bee color)
    rl.drawRectangleRounded(rl.Rectangle.init(px, py, 5, h), 0.8, 4, accent);

    // border state
    const border = if (hovered and afford) C.yellow else if (afford) accent else C.surface2;
    const thick: f32 = if (hovered and afford) 2.5 else 1.5;
    rl.drawRectangleRoundedLinesEx(cardRect, 0.18, 6, thick, border);

    // bee icon (tinted)
    const iconSize: f32 = 38;
    const iconX = px + 14;
    const iconY = py + (h - iconSize) / 2;
    const src = rl.Rectangle.init(0, 0, 32, 32);
    const dst = rl.Rectangle.init(iconX, iconY, iconSize, iconSize);
    const tint = if (afford) accent else rl.Color.init(accent.r, accent.g, accent.b, 120);
    rl.drawTexturePro(ctx.textures.bee, src, dst, rl.Vector2.init(0, 0), 0, tint);

    // name + owned count + perk
    const textX = @as(i32, @intFromFloat(px + 54));
    text.draw(name, textX, @as(i32, @intFromFloat(py + 7)), 19, if (afford) C.text else C.subtext0);
    if (owned > 0) {
        const ownedLabel = rl.textFormat("×%d", .{owned});
        const nameW = text.measure(name, 19);
        text.draw(ownedLabel, textX + nameW + 8, @as(i32, @intFromFloat(py + 10)), 15, accentDimmed(accent));
    }
    text.draw(perk, textX, @as(i32, @intFromFloat(py + 35)), 16, C.subtext0);

    // cost pill on right: honey-drop icon + amount (x qty when buying bulk)
    var cbuf: [32]u8 = undefined;
    const cstr = format.formatShort(totalCost, &cbuf);
    const costLabel = if (qty > 1) rl.textFormat("%s  x%d", .{ cstr.ptr, qty }) else rl.textFormat("%s", .{cstr.ptr});
    const costSize: i32 = 17;
    const costW = text.measure(costLabel, costSize);
    const dropR: f32 = 5.5;
    const dropSpan: f32 = dropR * 2 + 6;
    const contentW: f32 = @as(f32, @floatFromInt(costW)) + dropSpan;
    const pillW: f32 = contentW + 22;
    const pillH: f32 = 28;
    const pillX = px + w - pillW - 10;
    const pillY = py + (h - pillH) / 2;
    const pillColor = if (afford) C.yellow else C.surface1;
    const pillTextColor = if (afford) C.base else C.overlay0;
    rl.drawRectangleRounded(rl.Rectangle.init(pillX, pillY, pillW, pillH), 0.6, 6, pillColor);
    // Icon + amount centered as one group inside the pill.
    const contentX = pillX + (pillW - contentW) / 2;
    icons.drawHoneyDrop(contentX + dropR, pillY + pillH / 2 + dropR * 0.65, dropR, pillTextColor);
    const costY = pillY + (pillH - @as(f32, @floatFromInt(costSize))) / 2;
    text.draw(costLabel, @as(i32, @intFromFloat(contentX + dropSpan)), @as(i32, @intFromFloat(costY)), costSize, pillTextColor);

    if (hovered and afford and rl.isMouseButtonPressed(rl.MouseButton.left)) {
        out.* = .{ .buy = .{ .action = buyAction, .qty = qty } };
    }

    return y + h + 6;
}

/// Three small toggle chips (x1 x10 x25) right-aligned at (rightX, y).
fn drawQtyChips(rightX: f32, y: f32, mouse: rl.Vector2) void {
    const C = theme.CatppuccinMocha.Color;
    const chipH: f32 = 22;
    const gap: f32 = 4;
    var x = rightX;
    var i: usize = BUY_QTYS.len;
    while (i > 0) {
        i -= 1;
        const label = rl.textFormat("x%d", .{BUY_QTYS[i]});
        const tw: f32 = @floatFromInt(text.measure(label, 14));
        const chipW = tw + 14;
        x -= chipW;
        const rect = rl.Rectangle.init(x, y, chipW, chipH);
        const selected = i == buyQtyIndex;
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        rl.drawRectangleRounded(rect, 0.4, 4, if (selected) C.yellow else if (hovered) C.surface2 else C.surface1);
        text.draw(label, @intFromFloat(x + 7), @intFromFloat(y + 4), 14, if (selected) C.base else C.subtext1);
        if (hovered and rl.isMouseButtonPressed(rl.MouseButton.left)) buyQtyIndex = i;
        x -= gap;
    }
}

fn drawPrestigeCard(x: f32, y: f32, w: f32, mouse: rl.Vector2, prestige: *const prestige_mod.PrestigeState, out: *SidePanelAction) f32 {
    const C = theme.CatppuccinMocha.Color;
    const h: f32 = 92;
    const rect = rl.Rectangle.init(x, y, w, h);
    const hovered = rl.checkCollisionPointRec(mouse, rect);

    rl.drawRectangleRounded(rect, 0.15, 6, C.surface0);
    const border = if (hovered) C.pink else C.mauve;
    rl.drawRectangleRoundedLinesEx(rect, 0.15, 6, 2, border);

    // crown-ish dots
    const crownX = @as(i32, @intFromFloat(x + 14));
    const crownY = @as(i32, @intFromFloat(y + 14));
    rl.drawCircle(crownX, crownY + 6, 5, C.mauve);
    rl.drawCircle(crownX + 10, crownY, 6, C.pink);
    rl.drawCircle(crownX + 22, crownY + 6, 5, C.mauve);

    const jellyText = rl.textFormat(locale.tr("RJ %d  ·  x%.2f", "GR %d  ·  x%.2f"), .{ prestige.royalJelly, prestige.globalMul() });
    text.draw(jellyText, @as(i32, @intFromFloat(x + 44)), @as(i32, @intFromFloat(y + 6)), 18, C.pink);

    const runText = rl.textFormat(locale.tr("Run: %.0f honey", "Partida: %.0f mel"), .{prestige.thisRunHoney});
    text.draw(runText, @as(i32, @intFromFloat(x + 44)), @as(i32, @intFromFloat(y + 31)), 16, C.subtext1);

    // button row at bottom of card
    const btnY = y + 58;
    const btnH: f32 = 28;
    const btnRect = rl.Rectangle.init(x + 12, btnY, w - 24, btnH);
    const btnHovered = rl.checkCollisionPointRec(mouse, btnRect);
    const btnBg = if (btnHovered) C.mauve else C.surface1;
    rl.drawRectangleRounded(btnRect, 0.5, 6, btnBg);
    const btnText = locale.tr("Prestige", "Prestígio");
    const btnTW = text.measure(btnText, 17);
    text.draw(btnText, @as(i32, @intFromFloat(x + 12 + (w - 24) / 2)) - @divFloor(btnTW, 2), @as(i32, @intFromFloat(btnY + 3)), 17, if (btnHovered) C.base else C.text);

    if (btnHovered and rl.isMouseButtonPressed(rl.MouseButton.left)) {
        out.* = .open_prestige;
    }

    return y + h + 8;
}

fn accentDimmed(accent: rl.Color) rl.Color {
    return rl.Color.init(accent.r, accent.g, accent.b, 190);
}
