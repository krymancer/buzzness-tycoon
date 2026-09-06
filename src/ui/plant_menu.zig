//! Compact "plant a flower" chooser that opens when the player clicks an
//! meadow tile. Eight rows (one per flower type) with sprite, name and
//! cost, plus "Clear plan"; clicking outside or pressing Esc closes it.
//!
//! Picking a type plants it on the tile and arms it as a brush: dragging
//! across the meadow then paints the plan (and plants where honey allows)
//! until a right-click / Esc / B drops the brush.

const rl = @import("raylib");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const input = @import("../input.zig");
const format = @import("../format.zig");
const locale = @import("../localization.zig");
const utils = @import("../utils.zig");
const icons = @import("icons.zig");
const spawners = @import("../spawners.zig");
const Textures = @import("../textures.zig").Textures;
const Flowers = @import("../textures.zig").Flowers;
const Resources = @import("../resources.zig").Resources;

pub const Action = union(enum) {
    none,
    close,
    plant: Flowers,
    /// Arm the eraser: dragging clears planned cells.
    erase,
    remove_flowers,
};

pub const State = struct {
    open: bool = false,
    tileX: i32 = 0,
    tileY: i32 = 0,
    /// Armed flower brush (paint the plan / plant on drag).
    brush: ?Flowers = null,
    eraser: bool = false,
    remover: bool = false,
    waitForRelease: bool = false,
    /// Last tile painted this drag, so holding still doesn't re-paint.
    lastPaintX: i32 = -1,
    lastPaintY: i32 = -1,

    pub fn openAt(self: *@This(), x: i32, y: i32) void {
        self.open = true;
        self.lastPaintX = -1;
        self.lastPaintY = -1;
        self.tileX = x;
        self.tileY = y;
    }

    pub fn brushActive(self: *const @This()) bool {
        return self.brush != null or self.eraser or self.remover;
    }

    pub fn dropBrush(self: *@This()) void {
        self.brush = null;
        self.eraser = false;
        self.remover = false;
        self.waitForRelease = false;
        self.lastPaintX = -1;
        self.lastPaintY = -1;
    }
};

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    resources: *const Resources,
    textures: *const Textures,
    removalUnlocked: bool = false,
};

const ROW_H: f32 = 44;
const PANEL_W: f32 = 280;
const PAD: f32 = 8;
/// Garden planning is available in normal play.
pub var planningEnabled: bool = true;

const Entry = struct { flower: Flowers, cost: f32 };
const ENTRIES = [_]Entry{
    .{ .flower = .dandelion, .cost = spawners.FLOWER_COSTS.dandelion },
    .{ .flower = .rose, .cost = spawners.FLOWER_COSTS.rose },
    .{ .flower = .tulip, .cost = spawners.FLOWER_COSTS.tulip },
    .{ .flower = .pink_tulip, .cost = Flowers.pink_tulip.stats().plantCost },
    .{ .flower = .poppy, .cost = Flowers.poppy.stats().plantCost },
    .{ .flower = .hyacinth, .cost = Flowers.hyacinth.stats().plantCost },
    .{ .flower = .red_tulip, .cost = Flowers.red_tulip.stats().plantCost },
    .{ .flower = .iris, .cost = Flowers.iris.stats().plantCost },
};

pub fn flowerName(f: Flowers) [:0]const u8 {
    return switch (f) {
        .rose => locale.tr("Rose", "Rosa"),
        .tulip => locale.tr("Tulip", "Tulipa"),
        .dandelion => locale.tr("Dandelion", "Dente-de-leão"),
        .pink_tulip => locale.tr("Pink Tulip", "Tulipa Rosa"),
        .poppy => locale.tr("Poppy", "Papoula"),
        .hyacinth => locale.tr("Hyacinth", "Jacinto"),
        .red_tulip => locale.tr("Red Tulip", "Tulipa Vermelha"),
        .iris => locale.tr("Iris", "Íris"),
    };
}

/// One-line niche per type so the choice is visible (#71); numbers live in
/// components.FlowerType.stats.
fn flowerHint(f: Flowers) [:0]const u8 {
    return switch (f) {
        .rose => locale.tr("balanced", "equilibrada"),
        .tulip => locale.tr("rich pollen · slow · lasting", "muito pólen · lenta · duradoura"),
        .dandelion => locale.tr("light pollen · quick · brief", "pouco pólen · rápida · breve"),
        .pink_tulip => locale.tr("quick · light pollen", "rápida · pouco pólen"),
        .poppy => locale.tr("rich pollen · brief", "muito pólen · breve"),
        .hyacinth => locale.tr("steady pollen · lasting", "pólen constante · duradoura"),
        .red_tulip => locale.tr("rich pollen · slow", "muito pólen · lenta"),
        .iris => locale.tr("richest pollen · slowest", "mais pólen · mais lenta"),
    };
}

/// Draw the menu anchored under its tile and return what the player did.
pub fn draw(state: *const State, ctx: Context) Action {
    const C = theme.CatppuccinMocha.Color;
    const ERASE_H: f32 = 30;
    const HINT_H: f32 = 16;
    const panelH: f32 = PAD * 2 + 24 + ROW_H * ENTRIES.len + (if (planningEnabled) ERASE_H * 2 + HINT_H else 0);

    // Anchor just below the tile's diamond, clamped to the screen.
    const tilePos = utils.isoToXY(@floatFromInt(state.tileX), @floatFromInt(state.tileY), 32, 32, ctx.gridOffset.x, ctx.gridOffset.y, ctx.gridScale);
    var px = tilePos.x + 16 * ctx.gridScale - PANEL_W / 2;
    var py = tilePos.y + 16 * ctx.gridScale + 6;
    px = @max(8, @min(px, ctx.screenWidth - PANEL_W - 8));
    py = @max(8, @min(py, ctx.screenHeight - panelH - 8));
    const panel = rl.Rectangle.init(px, py, PANEL_W, panelH);

    rl.drawRectangleRounded(panel, 0.12, 6, C.mantle);
    rl.drawRectangleRoundedLinesEx(panel, 0.12, 6, 2, C.green);
    text.draw(locale.tr("Plant", "Plantar"), @intFromFloat(px + PAD + 2), @intFromFloat(py + PAD), 18, C.green);

    const mouse = input.pointerPos();
    const clicked = input.confirmPressed();
    var action: Action = .none;

    for (ENTRIES, 0..) |entry, i| {
        const ry = py + PAD + 24 + ROW_H * @as(f32, @floatFromInt(i));
        const row = rl.Rectangle.init(px + PAD, ry, PANEL_W - PAD * 2, ROW_H - 4);
        input.registerHotspot(row);
        const afford = ctx.resources.honey >= entry.cost;
        const hovered = rl.checkCollisionPointRec(mouse, row);

        rl.drawRectangleRounded(row, 0.25, 4, if (hovered and afford) C.surface1 else C.surface0);
        rl.drawRectangleRoundedLinesEx(row, 0.25, 4, 1, if (hovered and afford) C.green else C.surface2);

        // Grown-stage sprite (frame 4) as the icon.
        const tex = ctx.textures.getFlowerTexture(entry.flower);
        const src = rl.Rectangle.init(4 * 32, 0, 32, 32);
        const iconS: f32 = 30;
        const dst = rl.Rectangle.init(row.x + 6, row.y + (row.height - iconS) / 2, iconS, iconS);
        rl.drawTexturePro(tex, src, dst, rl.Vector2.init(0, 0), 0, if (afford) rl.Color.white else C.overlay0);

        text.draw(flowerName(entry.flower), @intFromFloat(row.x + 44), @intFromFloat(row.y + 5), 16, if (afford) C.text else C.overlay0);
        text.draw(flowerHint(entry.flower), @intFromFloat(row.x + 44), @intFromFloat(row.y + 24), 11, if (afford) C.subtext0 else C.overlay0);

        var cbuf: [32]u8 = undefined;
        const cstr = format.formatShort(entry.cost, &cbuf);
        const costLabel = rl.textFormat("%s", .{cstr.ptr});
        const cw: f32 = @floatFromInt(text.measure(costLabel, 15));
        const dropR: f32 = 4.5;
        const cx = row.x + row.width - cw - 10;
        icons.drawHoneyDrop(cx - dropR - 5, row.y + row.height / 2 + dropR * 0.65, dropR, if (afford) C.yellow else C.overlay0);
        text.draw(costLabel, @intFromFloat(cx), @intFromFloat(row.y + 12), 15, if (afford) C.yellow else C.overlay0);

        if (clicked and hovered and (afford or planningEnabled)) action = .{ .plant = entry.flower };
    }

    if (planningEnabled) {
        // "Clear plan" eraser row.
        const ey = py + PAD + 24 + ROW_H * ENTRIES.len;
        const erow = rl.Rectangle.init(px + PAD, ey, PANEL_W - PAD * 2, ERASE_H - 4);
        input.registerHotspot(erow);
        const ehov = rl.checkCollisionPointRec(mouse, erow);
        rl.drawRectangleRounded(erow, 0.25, 4, if (ehov) C.surface1 else C.surface0);
        rl.drawRectangleRoundedLinesEx(erow, 0.25, 4, 1, if (ehov) C.red else C.surface2);
        const elabel = locale.tr("Clear plan (eraser)", "Limpar plano (borracha)");
        text.draw(elabel, @intFromFloat(erow.x + 10), @intFromFloat(erow.y + 5), 14, if (ehov) C.red else C.subtext1);
        if (clicked and ehov) action = .erase;

        const removeRow = rl.Rectangle.init(px + PAD, ey + ERASE_H, PANEL_W - PAD * 2, ERASE_H - 4);
        if (ctx.removalUnlocked) input.registerHotspot(removeRow);
        const removeHover = ctx.removalUnlocked and rl.checkCollisionPointRec(mouse, removeRow);
        rl.drawRectangleRounded(removeRow, 0.25, 4, if (removeHover) C.surface1 else C.surface0);
        rl.drawRectangleRoundedLinesEx(removeRow, 0.25, 4, 1, if (removeHover) C.red else C.surface2);
        const removalLabel = if (ctx.removalUnlocked) locale.tr("Remove flowers + plans", "Remover flores + planos") else locale.tr("Removal Brush · unlock in tree", "Pincel de Remoção · na árvore");
        text.draw(removalLabel, @intFromFloat(removeRow.x + 10), @intFromFloat(removeRow.y + 5), 14, if (removeHover) C.red else if (ctx.removalUnlocked) C.peach else C.overlay0);
        if (clicked and removeHover) action = .remove_flowers;

        // Brush hint.
        const hint = if (input.gamepadActive()) locale.tr("Hold A: use brush · B: stop", "Segure A: usar pincel · B: sair") else locale.tr("Drag: use brush · Esc: stop", "Arraste: usar pincel · Esc: sair");
        text.draw(hint, @intFromFloat(px + PAD + 2), @intFromFloat(ey + ERASE_H * 2 - 2), 11, C.overlay1);
    }

    // Click anywhere outside the panel closes it.
    if (clicked and action == .none and !rl.checkCollisionPointRec(mouse, panel)) action = .close;
    return action;
}
