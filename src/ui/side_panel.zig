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
const Textures = @import("../textures.zig").Textures;
const popups = @import("popups.zig");
const locale = @import("../localization.zig");

pub const PANEL_WIDTH: f32 = 360;

pub const SidePanelContext = struct {
    screenWidth: f32,
    screenHeight: f32,
    resources: *const Resources,
    beeCount: usize,
    beehiveFactor: f32,
    treeState: *const upgrade_tree.State,
    prestige: *const prestige_mod.PrestigeState,
    textures: *const Textures,
};

pub const SidePanelAction = union(enum) {
    none,
    open_tree,
    open_prestige,
    buy: popups.TilePopupAction,
};

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

    // Bees section
    y = drawSectionHeader(contentX, y, contentW, locale.tr("Bees", "Abelhas"), C.yellow);
    const honey = ctx.resources.honey;

    y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Worker", "Operária"), locale.tr("+pollen", "+pólen"), spawners.BEE_TYPE_COSTS.worker, C.text, true, &action, .buy_worker_bee, honey);
    if (ctx.treeState.hasEffect(.bee_unlock_swift)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Swift", "Veloz"), locale.tr("2x speed", "velocidade 2x"), spawners.BEE_TYPE_COSTS.swift, C.blue, true, &action, .buy_swift_bee, honey);
    }
    if (ctx.treeState.hasEffect(.bee_unlock_efficient)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Efficient", "Eficiente"), locale.tr("2x pollen", "pólen 2x"), spawners.BEE_TYPE_COSTS.efficient, C.green, true, &action, .buy_efficient_bee, honey);
    }
    if (ctx.treeState.hasEffect(.bee_unlock_gardener)) {
        y = drawBeeCard(ctx, contentX, y, contentW, mouse, locale.tr("Gardener", "Jardineira"), locale.tr("plants flowers", "planta flores"), spawners.BEE_TYPE_COSTS.gardener, C.pink, true, &action, .buy_gardener_bee, honey);
    }

    // Prestige section
    if (ctx.prestige.hasUnlockedPrestige) {
        y = drawSectionHeader(contentX, y, contentW, locale.tr("Royal Jelly", "Geleia Real"), C.mauve);
        y = drawPrestigeCard(contentX, y, contentW, mouse, ctx.prestige, &action);
    }

    // Stats card at bottom
    drawStatsFooter(panelX, ctx.screenHeight, ctx.beeCount, ctx.beehiveFactor);

    return action;
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
    unlocked: bool,
    out: *SidePanelAction,
    buyAction: popups.TilePopupAction,
    honey: f32,
) f32 {
    const C = theme.CatppuccinMocha.Color;
    _ = unlocked;
    const h: f32 = 66;
    const rect = rl.Rectangle.init(x, y, w, h);
    const afford = honey >= cost;
    const hovered = rl.checkCollisionPointRec(mouse, rect);

    // card bg
    rl.drawRectangleRounded(rect, 0.18, 6, C.surface0);

    // accent strip on left (bee color)
    rl.drawRectangleRounded(rl.Rectangle.init(x, y, 5, h), 0.8, 4, accent);

    // border state
    const border = if (hovered and afford) C.yellow else if (afford) accent else C.surface2;
    const thick: f32 = if (hovered and afford) 2.5 else 1.5;
    rl.drawRectangleRoundedLinesEx(rect, 0.18, 6, thick, border);

    // bee icon (tinted)
    const iconSize: f32 = 38;
    const iconX = x + 14;
    const iconY = y + (h - iconSize) / 2;
    const src = rl.Rectangle.init(0, 0, 32, 32);
    const dst = rl.Rectangle.init(iconX, iconY, iconSize, iconSize);
    const tint = if (afford) accent else rl.Color.init(accent.r, accent.g, accent.b, 120);
    rl.drawTexturePro(ctx.textures.bee, src, dst, rl.Vector2.init(0, 0), 0, tint);

    // name + perk
    const textX = @as(i32, @intFromFloat(x + 54));
    text.draw(name, textX, @as(i32, @intFromFloat(y + 7)), 19, if (afford) C.text else C.subtext0);
    text.draw(perk, textX, @as(i32, @intFromFloat(y + 35)), 16, C.subtext0);

    // cost pill on right
    var cbuf: [32]u8 = undefined;
    const cstr = format.formatShort(cost, &cbuf);
    const costLabel = rl.textFormat("%s", .{cstr.ptr});
    const costW = text.measure(costLabel, 17);
    const pillW: f32 = @as(f32, @floatFromInt(costW)) + 18;
    const pillH: f32 = 28;
    const pillX = x + w - pillW - 10;
    const pillY = y + (h - pillH) / 2;
    const pillColor = if (afford) C.yellow else C.surface1;
    const pillTextColor = if (afford) C.base else C.overlay0;
    rl.drawRectangleRounded(rl.Rectangle.init(pillX, pillY, pillW, pillH), 0.6, 6, pillColor);
    text.draw(costLabel, @as(i32, @intFromFloat(pillX + 9)), @as(i32, @intFromFloat(pillY + 3)), 17, pillTextColor);

    if (hovered and afford and rl.isMouseButtonPressed(rl.MouseButton.left)) {
        out.* = .{ .buy = buyAction };
    }

    return y + h + 6;
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

fn drawStatsFooter(panelX: f32, screenHeight: f32, beeCount: usize, beehiveFactor: f32) void {
    const C = theme.CatppuccinMocha.Color;
    const h: f32 = 44;
    const y = screenHeight - h - 10;
    const x = panelX + 14;
    const w = PANEL_WIDTH - 28;
    const rect = rl.Rectangle.init(x, y, w, h);
    rl.drawRectangleRounded(rect, 0.4, 6, C.surface0);
    rl.drawRectangleRoundedLinesEx(rect, 0.4, 6, 1, C.surface1);

    const stats = rl.textFormat(locale.tr("Bees %d   Factor x%.1f", "Abelhas %d   Fator x%.1f"), .{ beeCount, beehiveFactor });
    const tw = text.measure(stats, 18);
    const tx = @as(i32, @intFromFloat(x + w / 2)) - @divFloor(tw, 2);
    text.draw(stats, tx, @as(i32, @intFromFloat(y + 9)), 18, C.subtext1);
}
