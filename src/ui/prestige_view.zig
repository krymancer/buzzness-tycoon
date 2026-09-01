//! Prestige panel: the "Ascend" card (what this run converts into) next to
//! the Royal Shop, where lifetime Royal Jelly buys permanent perks.
//!
//! Spending never lowers the income multiplier (that comes from lifetime
//! jelly), so the shop is pure upside and the panel says so.

const rl = @import("raylib");
const std = @import("std");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const format = @import("../format.zig");
const locale = @import("../localization.zig");
const icons = @import("icons.zig");
const action_hud = @import("action_hud.zig");
const input = @import("../input.zig");
const widgets = @import("widgets.zig");
const clock = @import("../clock.zig");
const prestige_mod = @import("../prestige.zig");
const Textures = @import("../textures.zig").Textures;

pub const Action = union(enum) {
    none,
    close,
    /// Ascend with the gain the panel displayed.
    confirm: u64,
    buy: prestige_mod.ShopItem,
};

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    prestige: *const prestige_mod.PrestigeState,
    textures: *const Textures,
    /// The Prestige tree node is owned in the current run. The panel opens
    /// once prestige was ever unlocked; ascending again and buying from the
    /// Royal Shop both need the node re-bought each run.
    ascendUnlocked: bool,
};

const ITEMS = [_]prestige_mod.ShopItem{ .queens_blessing, .jelly_refinery, .royal_meadow, .busy_bees, .royal_retinue, .wholesale_contract, .queens_count };

const ROW_H: f32 = 72;
const FLASH_TIME: f32 = 0.45;

/// Per-row purchase glow, plus a hover "wiggle" seed so rows animate
/// independently.
var rowFlash: [prestige_mod.SHOP_ITEM_COUNT]f32 = @splat(0);

pub fn flashRow(item: prestige_mod.ShopItem) void {
    rowFlash[@intFromEnum(item)] = FLASH_TIME;
}

fn withAlpha(c: rl.Color, a: u8) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, a);
}

fn fmtInt(v: u64, buf: []u8) [:0]const u8 {
    return format.formatShort(@floatFromInt(v), buf);
}

/// Multiplier label: two decimals while small, short-suffixed when large.
fn fmtMul(v: f32, buf: []u8) [:0]const u8 {
    if (v < 1000.0) return std.fmt.bufPrintZ(buf, "{d:.2}", .{v}) catch "?";
    return format.formatShort(v, buf);
}

pub fn draw(ctx: Context) Action {
    const C = theme.CatppuccinMocha.Color;
    const now: f32 = @floatCast(clock.time());
    const dt = rl.getFrameTime();
    for (&rowFlash) |*f| f.* = @max(0, f.* - dt);

    rl.drawRectangle(0, 0, @intFromFloat(ctx.screenWidth), @intFromFloat(ctx.screenHeight), C.modalOverlay);

    const panelW: f32 = @min(ctx.screenWidth - 40, 1000);
    const panelH: f32 = @min(ctx.screenHeight - 40, 580);
    const panelX: f32 = (ctx.screenWidth - panelW) / 2;
    const panelY: f32 = (ctx.screenHeight - panelH) / 2;
    const panel = rl.Rectangle.init(panelX, panelY, panelW, panelH);
    input.registerBlock(panel);

    // Panel with a slowly breathing mauve/pink border.
    rl.drawRectangleRounded(panel, 0.03, 10, C.mantle);
    const breathe = 0.5 + 0.5 * @sin(now * 1.6);
    const border = lerpColor(C.mauve, C.pink, breathe);
    rl.drawRectangleRoundedLinesEx(panel, 0.03, 10, 2, border);

    drawHeader(ctx, panelX, panelY, panelW, now);

    var action: Action = .none;
    const contentY = panelY + 64;
    const contentH = panelH - 64 - 66;
    const gap: f32 = 18;
    const leftW: f32 = @max(300, (panelW - 40 - gap) * 0.34);
    const rightW = panelW - 40 - gap - leftW;
    const leftX = panelX + 20;
    const rightX = leftX + leftW + gap;

    drawAscendCard(ctx, leftX, contentY, leftW, contentH, now, &action);
    drawShopCard(ctx, rightX, contentY, rightW, contentH, &action);

    // Close button, bottom-right.
    const closeW: f32 = 140;
    const closeH: f32 = 44;
    if (widgets.button(rl.Rectangle.init(panelX + panelW - closeW - 14, panelY + panelH - closeH - 14, closeW, closeH), locale.tr("Close", "Fechar"))) {
        action = .close;
    }

    // Footer note: the one rule players worry about.
    const note = locale.tr("Spending Royal Jelly never lowers your multiplier.", "Gastar Geleia Real nunca reduz seu multiplicador.");
    text.draw(note, @intFromFloat(panelX + 20), @intFromFloat(panelY + panelH - 42), 15, C.overlay1);

    return action;
}

fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const lerp = struct {
        fn f(x: u8, y: u8, k: f32) u8 {
            return @intFromFloat(@as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(x))) * k);
        }
    }.f;
    return rl.Color.init(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), 255);
}

fn drawHeader(ctx: Context, panelX: f32, panelY: f32, panelW: f32, now: f32) void {
    const C = theme.CatppuccinMocha.Color;
    // Crown bobbing gently next to the title.
    const bob = 2.0 * @sin(now * 2.2);
    icons.drawCrown(panelX + 44, panelY + 32 + bob, 34, C.yellow, C.pink);
    text.draw(locale.tr("Prestige", "Prestígio"), @intFromFloat(panelX + 72), @intFromFloat(panelY + 12), 36, C.mauve);

    // Balance pill on the right: spendable jelly + current multiplier.
    var jbuf: [32]u8 = undefined;
    var mbuf: [32]u8 = undefined;
    const balance = rl.textFormat(locale.tr("%s Royal Jelly", "%s de Geleia Real"), .{fmtInt(ctx.prestige.availableJelly(), &jbuf).ptr});
    const mul = rl.textFormat("x%s", .{fmtMul(ctx.prestige.globalMul(), &mbuf).ptr});
    const bw = text.measure(balance, 20);
    const mw = text.measure(mul, 20);
    const pillW: f32 = @floatFromInt(bw + mw + 72);
    const pillH: f32 = 40;
    const pillX = panelX + panelW - pillW - 18;
    const pillY = panelY + 14;
    const pill = rl.Rectangle.init(pillX, pillY, pillW, pillH);
    rl.drawRectangleRounded(pill, 0.5, 8, C.surface0);
    rl.drawRectangleRoundedLinesEx(pill, 0.5, 8, 1, C.surface2);
    icons.drawHoneyDrop(pillX + 20, pillY + 24, 6, C.pink);
    text.draw(balance, @intFromFloat(pillX + 34), @intFromFloat(pillY + 9), 20, C.pink);
    rl.drawRectangleRec(rl.Rectangle.init(pillX + 34 + @as(f32, @floatFromInt(bw)) + 12, pillY + 10, 1, pillH - 20), C.surface2);
    text.draw(mul, @intFromFloat(pillX + 34 + @as(f32, @floatFromInt(bw)) + 24), @intFromFloat(pillY + 9), 20, C.yellow);
}

fn cardFrame(x: f32, y: f32, w: f32, h: f32, title: [:0]const u8, accent: rl.Color) void {
    const C = theme.CatppuccinMocha.Color;
    const rect = rl.Rectangle.init(x, y, w, h);
    rl.drawRectangleRounded(rect, 0.05, 8, C.base);
    rl.drawRectangleRoundedLinesEx(rect, 0.05, 8, 1, C.surface1);
    text.draw(title, @intFromFloat(x + 16), @intFromFloat(y + 10), 22, accent);
    rl.drawRectangleRec(rl.Rectangle.init(x + 16, y + 40, w - 32, 1), C.surface1);
}

fn drawAscendCard(ctx: Context, x: f32, y: f32, w: f32, h: f32, now: f32, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    cardFrame(x, y, w, h, locale.tr("Ascend", "Ascender"), C.pink);

    const p = ctx.prestige;
    const gain = p.gainFromReset();
    const canAscend = gain > 0 and ctx.ascendUnlocked;
    var next = p.*;
    next.resetRun(gain);

    // Drifting sparkles behind the numbers, brighter when there's a gain.
    drawSparkles(x, y + 44, w, h - 110, now, if (canAscend) 200 else 70);

    const lx: i32 = @intFromFloat(x + 18);
    var ly: f32 = y + 54;
    const labelSize: i32 = 16;
    const valueSize: i32 = 26;

    var runBuf: [32]u8 = undefined;
    text.draw(locale.tr("This run", "Nesta partida"), lx, @intFromFloat(ly), labelSize, C.subtext0);
    ly += 20;
    const runLabel = rl.textFormat(locale.tr("%s honey", "%s de mel"), .{format.formatShort(p.thisRunHoney, &runBuf).ptr});
    text.draw(runLabel, lx, @intFromFloat(ly), valueSize, C.yellow);
    ly += 44;

    text.draw(locale.tr("Royal Jelly gained", "Geleia Real recebida"), lx, @intFromFloat(ly), labelSize, C.subtext0);
    ly += 20;
    // The headline number pulses so the reward reads as the point of it all.
    var gainBuf: [32]u8 = undefined;
    const gainLabel = rl.textFormat("+%s", .{fmtInt(gain, &gainBuf).ptr});
    const pulse = if (canAscend) 0.5 + 0.5 * @sin(now * 3.0) else 0;
    const gainSize: i32 = 40 + @as(i32, @intFromFloat(pulse * 3));
    const glow = withAlpha(C.pink, @intFromFloat(40 + pulse * 60));
    if (canAscend) {
        const gw: f32 = @floatFromInt(text.measure(gainLabel, gainSize));
        rl.drawRectangleRounded(rl.Rectangle.init(x + 12, ly - 2, gw + 14, @as(f32, @floatFromInt(gainSize)) + 4), 0.4, 6, glow);
    }
    text.draw(gainLabel, lx, @intFromFloat(ly), gainSize, if (canAscend) C.pink else C.overlay0);
    ly += 56;

    text.draw(locale.tr("Multiplier", "Multiplicador"), lx, @intFromFloat(ly), labelSize, C.subtext0);
    ly += 20;
    var m1: [32]u8 = undefined;
    var m2: [32]u8 = undefined;
    const curLabel = rl.textFormat("x%s", .{fmtMul(p.globalMul(), &m1).ptr});
    const nextLabel = rl.textFormat("x%s", .{fmtMul(next.globalMul(), &m2).ptr});
    text.draw(curLabel, lx, @intFromFloat(ly), 22, C.subtext1);
    const cw = text.measure(curLabel, 22);
    const arrowX = x + 18 + @as(f32, @floatFromInt(cw)) + 18;
    icons.drawArrow(arrowX, ly + 13, 7, .right, C.overlay1);
    text.draw(nextLabel, @intFromFloat(arrowX + 18), @intFromFloat(ly), valueSize, if (canAscend) C.green else C.overlay0);
    ly += 44;

    const noteW: i32 = @intFromFloat(w - 36);
    if (!ctx.ascendUnlocked) {
        drawFitted(locale.tr("Buy Prestige in the upgrade tree to ascend this run.", "Compre Prestígio na árvore para ascender nesta partida."), lx, @intFromFloat(ly), 15, noteW, C.peach);
    } else if (canAscend) {
        drawFitted(locale.tr("Resets honey, tree, labs, grid, bees.", "Reinicia mel, árvore, labs, grade e abelhas."), lx, @intFromFloat(ly), 15, noteW, C.red);
    } else {
        drawFitted(locale.tr("Make more honey this run to earn jelly.", "Faça mais mel nesta partida para ganhar geleia."), lx, @intFromFloat(ly), 15, noteW, C.overlay1);
    }

    const btnH: f32 = 48;
    const btnRect = rl.Rectangle.init(x + 16, y + h - btnH - 16, w - 32, btnH);
    if (widgets.buttonEx(btnRect, locale.tr("Ascend", "Ascender"), .{ .enabled = canAscend, .fontSize = 22 })) {
        out.* = .{ .confirm = gain };
    }
}

/// A handful of slow, looping motes drifting upward inside a region; each
/// mote's path is a pure function of time, so nothing needs storing.
fn drawSparkles(x: f32, y: f32, w: f32, h: f32, now: f32, alpha: u8) void {
    const C = theme.CatppuccinMocha.Color;
    const count = 14;
    for (0..count) |i| {
        const fi: f32 = @floatFromInt(i);
        const speed = 0.06 + 0.04 * @mod(fi * 0.37, 1.0);
        const phase = @mod(now * speed + fi * 0.173, 1.0);
        const sx = x + 10 + @mod(fi * 61.7 + 12.0 * @sin(now * 0.7 + fi), w - 20);
        const sy = y + h - phase * h;
        // Fade in at the bottom and out at the top.
        const fade = @min(1.0, @min(phase * 4.0, (1.0 - phase) * 4.0));
        const a: u8 = @intFromFloat(@as(f32, @floatFromInt(alpha)) * fade);
        const r = 1.2 + 1.3 * @mod(fi * 0.53, 1.0);
        rl.drawCircleV(rl.Vector2.init(sx, sy), r, withAlpha(if (i % 3 == 0) C.yellow else C.pink, a));
    }
}

fn drawShopCard(ctx: Context, x: f32, y: f32, w: f32, h: f32, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    cardFrame(x, y, w, h, locale.tr("Royal Shop", "Loja Real"), C.mauve);
    // Latin-1 font atlas: no em dash. Until the run owns the Prestige node
    // the shop is browse-only and the corner hint says why.
    const hint = if (ctx.ascendUnlocked)
        locale.tr("Permanent · survives every prestige", "Permanente · sobrevive a todo prestígio")
    else
        locale.tr("Buy Prestige in the upgrade tree to shop this run.", "Compre Prestígio na árvore para comprar nesta partida.");
    const hintCol = if (ctx.ascendUnlocked) C.overlay1 else C.peach;
    const hw = text.measure(hint, 14);
    text.draw(hint, @as(i32, @intFromFloat(x + w - 16)) - hw, @intFromFloat(y + 16), 14, hintCol);

    const mouse = input.pointerPos();
    var ry = y + 48;
    const rowW = w - 24;
    const availH = h - 56;
    const rowH = @min(ROW_H, availH / @as(f32, @floatFromInt(ITEMS.len)));
    for (ITEMS) |item| {
        drawShopRow(ctx, item, x + 12, ry, rowW, rowH - 4, mouse, out);
        ry += rowH;
    }
}

const ItemCopy = struct {
    name: [:0]const u8,
    desc: [:0]const u8,
    accent: rl.Color,
};

fn itemCopy(item: prestige_mod.ShopItem) ItemCopy {
    const C = theme.CatppuccinMocha.Color;
    return switch (item) {
        .queens_blessing => .{
            .name = locale.tr("Queen's Blessing", "Bênção da Rainha"),
            .desc = locale.tr("+10% honey from every delivery, per level.", "+10% de mel em toda entrega, por nível."),
            .accent = C.yellow,
        },
        .jelly_refinery => .{
            .name = locale.tr("Jelly Refinery", "Refinaria de Geleia"),
            .desc = locale.tr("+10% Royal Jelly per prestige, per level.", "+10% de Geleia Real por prestígio, por nível."),
            .accent = C.pink,
        },
        .royal_meadow => .{
            .name = locale.tr("Royal Meadow", "Campo Real"),
            .desc = locale.tr("Every run starts one meadow ring bigger. Grows now too.", "Toda partida começa com um anel a mais. Cresce agora também."),
            .accent = C.lavender,
        },
        .busy_bees => .{
            .name = locale.tr("Busy Bees", "Abelhas Ocupadas"),
            .desc = locale.tr("Every run starts with 8 extra bees per level.", "Toda partida começa com 8 abelhas a mais por nível."),
            .accent = C.peach,
        },
        .royal_retinue => .{
            .name = locale.tr("Royal Retinue", "Séquito Real"),
            .desc = locale.tr("Swift, Efficient and Gardener bees unlocked from the start.", "Abelhas Veloz, Eficiente e Jardineira liberadas desde o início."),
            .accent = C.teal,
        },
        .queens_count => .{
            .name = locale.tr("Queen's Count", "Contagem da Rainha"),
            .desc = locale.tr("Each bee type doubles its pollen at 10, 25, 50 and 100 owned, then at every doubling.", "Cada tipo de abelha dobra o pólen com 10, 25, 50 e 100 abelhas, e depois a cada dobro."),
            .accent = C.pink,
        },
        .wholesale_contract => .{
            .name = locale.tr("Wholesale Contract", "Contrato de Atacado"),
            .desc = locale.tr("One more bulk-buy step per level, beyond Bulk Order: up to x100K bees per click.", "Um passo a mais de compra em massa por nível, além do Pedido em Massa: até x100K abelhas por clique."),
            .accent = C.sapphire,
        },
    };
}

/// "Now · Next" line using the same formulas the game applies.
fn itemStatus(p: *const prestige_mod.PrestigeState, item: prestige_mod.ShopItem, buf: []u8) ?[:0]const u8 {
    const now = locale.tr("Now", "Agora");
    const nxt = locale.tr("Next", "Próx.");
    const lvl = p.shopLevel(item);
    const maxed = prestige_mod.shopSpec(item).isMaxed(lvl);
    switch (item) {
        .queens_blessing => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const cur = std.math.pow(f32, prestige_mod.BLESSING_PER_LEVEL, @floatFromInt(lvl));
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}", .{ now, fmtMul(cur, &b1) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(cur, &b1), nxt, fmtMul(cur * prestige_mod.BLESSING_PER_LEVEL, &b2) }) catch null;
        },
        .jelly_refinery => {
            const cur: u32 = @intFromFloat(@round(100.0 * prestige_mod.REFINERY_PER_LEVEL * @as(f32, @floatFromInt(lvl))));
            const step: u32 = @intFromFloat(@round(100.0 * prestige_mod.REFINERY_PER_LEVEL));
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: +{d}%", .{ now, cur }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: +{d}%  ·  {s}: +{d}%", .{ now, cur, nxt, cur + step }) catch null;
        },
        .royal_meadow => {
            const rings = locale.tr("rings", "anéis");
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: +{d} {s}", .{ now, lvl, rings }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: +{d} {s}  ·  {s}: +{d} {s}", .{ now, lvl, rings, nxt, lvl + 1, rings }) catch null;
        },
        .busy_bees => {
            const bees = locale.tr("bees", "abelhas");
            const cur = prestige_mod.BEES_PER_BUSY_LEVEL * @as(u32, lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: +{d} {s}", .{ now, cur, bees }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: +{d} {s}  ·  {s}: +{d} {s}", .{ now, cur, bees, nxt, cur + prestige_mod.BEES_PER_BUSY_LEVEL, bees }) catch null;
        },
        .royal_retinue, .queens_count => return null,
        .wholesale_contract => {
            var b1: [16]u8 = undefined;
            var b2: [16]u8 = undefined;
            const upto = locale.tr("up to", "até");
            const cur = action_hud.qtyLabel(action_hud.topQtyWithShopLevel(lvl), &b1);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {s} {s}", .{ now, upto, cur }) catch null;
            const next = action_hud.qtyLabel(action_hud.topQtyWithShopLevel(lvl + 1), &b2);
            return std.fmt.bufPrintZ(buf, "{s}: {s} {s}  ·  {s}: {s} {s}", .{ now, upto, cur, nxt, upto, next }) catch null;
        },
    }
}

fn drawShopRow(ctx: Context, item: prestige_mod.ShopItem, x: f32, y: f32, w: f32, h: f32, mouse: rl.Vector2, out: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const p = ctx.prestige;
    const copy = itemCopy(item);
    const lvl = p.shopLevel(item);
    const spec = prestige_mod.shopSpec(item);
    const maxed = spec.isMaxed(lvl);
    const afford = p.canBuyShop(item) and ctx.ascendUnlocked;
    const rect = rl.Rectangle.init(x, y, w, h);
    const hovered = rl.checkCollisionPointRec(mouse, rect);

    rl.drawRectangleRounded(rect, 0.15, 6, if (hovered and !maxed) C.surface1 else C.surface0);
    const borderCol = if (maxed) C.green else if (afford) copy.accent else C.surface2;
    rl.drawRectangleRoundedLinesEx(rect, 0.15, 6, if (afford or maxed) 2 else 1, borderCol);

    // Purchase glow: swells and fades in the item's accent.
    const flash = rowFlash[@intFromEnum(item)];
    if (flash > 0) {
        const t = flash / FLASH_TIME;
        rl.drawRectangleRounded(rect, 0.15, 6, withAlpha(copy.accent, @intFromFloat(90 * t)));
    }

    // Icon badge on the left.
    const badge: f32 = @min(44, h - 12);
    const bx = x + 10;
    const by = y + (h - badge) / 2;
    rl.drawRectangleRounded(rl.Rectangle.init(bx, by, badge, badge), 0.3, 6, C.mantle);
    drawItemIcon(ctx, item, bx + badge / 2, by + badge / 2, if (afford or maxed) copy.accent else C.overlay0);

    // Name + level, description, status. Text must stay clear of the buy
    // button on the right, so long (Portuguese) copy drops a font step.
    const btnW: f32 = 118;
    const btnH: f32 = 38;
    const tx: i32 = @intFromFloat(bx + badge + 12);
    const textAvail: i32 = @intFromFloat(x + w - btnW - 16 - (bx + badge + 12));
    var nameBuf: [64]u8 = undefined;
    const nameZ = if (lvl > 0)
        std.fmt.bufPrintZ(&nameBuf, "{s}  {s}{d}", .{ copy.name, locale.tr("Lv", "Nv"), lvl }) catch copy.name
    else
        copy.name;
    text.draw(nameZ, tx, @intFromFloat(y + 8), 19, if (maxed) C.green else C.text);
    drawFitted(copy.desc, tx, @intFromFloat(y + 31), 14, textAvail, C.subtext0);
    var statusBuf: [96]u8 = undefined;
    if (itemStatus(p, item, &statusBuf)) |st| {
        drawFitted(st, tx, @intFromFloat(y + 49), 14, textAvail, C.teal);
    } else if (maxed) {
        text.draw(locale.tr("Owned", "Adquirido"), tx, @intFromFloat(y + 49), 14, C.green);
    }

    // Buy button on the right: cost, or MAX once fully leveled.
    const btn = rl.Rectangle.init(x + w - btnW - 10, y + (h - btnH) / 2, btnW, btnH);
    if (maxed) {
        _ = widgets.buttonEx(btn, locale.tr("MAX", "MÁX"), .{ .enabled = false, .fontSize = 18 });
        return;
    }
    var cbuf: [32]u8 = undefined;
    const costLabel = rl.textFormat("%s RJ", .{format.formatShort(p.shopCost(item), &cbuf).ptr});
    if (widgets.buttonEx(btn, costLabel, .{ .enabled = afford, .fontSize = 18, .textColor = C.base })) {
        out.* = .{ .buy = item };
    }
}

/// Draw a line at `size`, stepping the font down (to a floor of 11) until it
/// fits `maxW`.
fn drawFitted(line: [:0]const u8, x: i32, y: i32, size: i32, maxW: i32, color: rl.Color) void {
    var s = size;
    while (s > 11 and text.measure(line, s) > maxW) s -= 1;
    text.draw(line, x, y + @divFloor(size - s, 2), s, color);
}

fn drawItemIcon(ctx: Context, item: prestige_mod.ShopItem, cx: f32, cy: f32, col: rl.Color) void {
    const C = theme.CatppuccinMocha.Color;
    switch (item) {
        .queens_blessing => icons.drawCrown(cx, cy, 22, col, C.pink),
        .jelly_refinery => icons.drawHoneyDrop(cx, cy + 4, 8, col),
        .royal_meadow => {
            // Isometric tile diamond, same glyph as the Grid Ring node.
            const rx: f32 = 12;
            const ry: f32 = 7;
            const top = rl.Vector2.init(cx, cy - ry);
            const left = rl.Vector2.init(cx - rx, cy);
            const right = rl.Vector2.init(cx + rx, cy);
            const bottom = rl.Vector2.init(cx, cy + ry);
            for ([_][3]rl.Vector2{ .{ top, left, right }, .{ bottom, right, left } }) |p| {
                rl.drawTriangle(p[0], p[1], p[2], col);
                rl.drawTriangle(p[2], p[1], p[0], col);
            }
        },
        .busy_bees => drawBee(ctx, cx, cy, 30, col),
        .royal_retinue => {
            // The three unlockable bee types, huddled.
            const dim = col.a < 255 or std.meta.eql(col, C.overlay0);
            drawBee(ctx, cx - 8, cy - 5, 20, if (dim) col else C.blue);
            drawBee(ctx, cx + 8, cy - 5, 20, if (dim) col else C.green);
            drawBee(ctx, cx, cy + 7, 20, if (dim) col else C.pink);
        },
        .queens_count => {
            // A crown over a pair of bees: the queen counting her workers.
            icons.drawCrown(cx, cy - 7, 14, col, C.pink);
            drawBee(ctx, cx - 8, cy + 7, 16, col);
            drawBee(ctx, cx + 8, cy + 7, 16, col);
        },
        .wholesale_contract => {
            // A crate of bees: a stacked pair with a small third on top.
            drawBee(ctx, cx - 7, cy + 4, 22, col);
            drawBee(ctx, cx + 7, cy + 4, 22, col);
            drawBee(ctx, cx, cy - 7, 18, col);
        },
    }
}

fn drawBee(ctx: Context, cx: f32, cy: f32, size: f32, tint: rl.Color) void {
    rl.drawTexturePro(
        ctx.textures.bee,
        rl.Rectangle.init(0, 0, 32, 32),
        rl.Rectangle.init(cx - size / 2, cy - size / 2, size, size),
        rl.Vector2.init(0, 0),
        0,
        tint,
    );
}
