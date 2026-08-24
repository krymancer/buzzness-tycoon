const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const input = @import("../input.zig");
const widgets = @import("widgets.zig");

const theme = @import("../theme.zig");
const format = @import("../format.zig");
const icons = @import("icons.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const Resources = @import("../resources.zig").Resources;
const Textures = @import("../textures.zig").Textures;
const locale = @import("../localization.zig");
const ui_scale = @import("../ui_scale.zig");
const labs = @import("../labs.zig");
const spawners = @import("../spawners.zig");
const bee_ai_system = @import("../ecs/systems/bee_ai_system.zig");
const lifespan_system = @import("../ecs/systems/lifespan_system.zig");
const flower_growth_system = @import("../ecs/systems/flower_growth_system.zig");

pub const TreeAction = union(enum) {
    none,
    close,
    purchase: upgrade_tree.NodeId,
};

const NODE_W: f32 = 158;
const NODE_H: f32 = 44;
const COL_SPACING: f32 = 174;
const ROW_SPACING: f32 = 56;
// Layout extents (cols -2..2, rows 0..6) at scale 1.
const MIN_COL: f32 = -2;
const MAX_COL: f32 = 2;
const MAX_ROW: f32 = 6;
const TREE_W: f32 = (MAX_COL - MIN_COL) * COL_SPACING + NODE_W;
const TREE_H: f32 = MAX_ROW * ROW_SPACING + NODE_H;
// Below this the tree stops shrinking to fit and scrolls instead.
const MIN_FIT_SCALE: f32 = 0.6;

// Scroll offset (logical px) when the tree doesn't fit; reset on open.
var scrollX: f32 = 0;
var scrollY: f32 = 0;
var dragging: bool = false;
var dragMoved: f32 = 0;
var lastMouse: rl.Vector2 = .{ .x = 0, .y = 0 };

pub fn resetScroll() void {
    scrollX = 0;
    scrollY = 0;
    dragging = false;
}

pub const TreeContext = struct {
    screenWidth: f32,
    screenHeight: f32,
    state: *const upgrade_tree.State,
    resources: *const Resources,
    textures: *const Textures,
};

const NodeStyle = struct {
    fill: rl.Color,
    border: rl.Color,
    borderThick: f32,
    nameColor: rl.Color,
    costColor: rl.Color,
    showOwned: bool = false,
};

fn styleFor(purchased: bool, maxed: bool, unlocked: bool, afford: bool) NodeStyle {
    const C = theme.CatppuccinMocha.Color;
    if (maxed) return .{
        .fill = C.surface0,
        .border = C.green,
        .borderThick = 3,
        .nameColor = C.green,
        .costColor = C.green,
        .showOwned = true,
    };
    if (!unlocked) return .{
        .fill = C.crust,
        .border = C.surface1,
        .borderThick = 1,
        .nameColor = C.overlay0,
        .costColor = C.overlay0,
    };
    // Owned repeatable nodes keep a green tint so "leveled" reads at a glance.
    if (afford) return .{
        .fill = C.surface0,
        .border = if (purchased) C.teal else C.blue,
        .borderThick = 3,
        .nameColor = C.text,
        .costColor = C.yellow,
    };
    return .{
        .fill = C.surface0,
        .border = if (purchased) C.green else C.surface2,
        .borderThick = 2,
        .nameColor = C.subtext1,
        .costColor = C.red,
    };
}

fn nodePos(node: *const upgrade_tree.Node, centerX: f32, topY: f32, s: f32) rl.Vector2 {
    const x = centerX + @as(f32, @floatFromInt(node.col)) * COL_SPACING * s - NODE_W * s / 2;
    const y = topY + @as(f32, @floatFromInt(node.row)) * ROW_SPACING * s;
    return rl.Vector2.init(x, y);
}

fn fs(size: i32, s: f32) i32 {
    return @max(9, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(size)) * s))));
}

pub fn draw(ctx: TreeContext) TreeAction {
    const C = theme.CatppuccinMocha.Color;

    rl.drawRectangle(0, 0, @intFromFloat(ctx.screenWidth), @intFromFloat(ctx.screenHeight), C.modalOverlay);

    const panelW: f32 = @min(ctx.screenWidth - 40, 1120);
    const panelH: f32 = @min(ctx.screenHeight - 40, 720);
    const panelX: f32 = (ctx.screenWidth - panelW) / 2;
    const panelY: f32 = (ctx.screenHeight - panelH) / 2;

    // Deeper panel bg so surface0 nodes read clearly on top
    rl.drawRectangleRounded(rl.Rectangle.init(panelX, panelY, panelW, panelH), 0.03, 10, C.mantle);
    rl.drawRectangleRoundedLinesEx(rl.Rectangle.init(panelX, panelY, panelW, panelH), 0.03, 10, 2, C.surface2);

    const title = locale.tr("Upgrade Tree", "Árvore de Melhorias");
    const titleX = @as(i32, @intFromFloat(panelX + panelW / 2)) - @divFloor(text.measure(title, 32), 2);
    text.draw(title, titleX, @as(i32, @intFromFloat(panelY + 10)), 32, C.mauve);

    // Honey stash pill (helps gauge affordability)
    var hbuf: [32]u8 = undefined;
    const hstr = format.formatShort(ctx.resources.honey, &hbuf);
    const honeyLabel = rl.textFormat(locale.tr("Honey: %s", "Mel: %s"), .{hstr.ptr});
    text.draw(honeyLabel, @as(i32, @intFromFloat(panelX + 18)), @as(i32, @intFromFloat(panelY + 20)), 19, C.yellow);

    // Content area between the title row and the legend/close row.
    const contentX = panelX + 20;
    const contentY = panelY + 60;
    const contentW = panelW - 40;
    const contentH = panelH - 60 - 78;

    // Auto-fit: shrink the layout so the whole tree shows whenever it can
    // (big UI scale => small logical panel); below MIN_FIT_SCALE, scroll.
    const fit = @min(contentW / TREE_W, contentH / TREE_H);
    const s: f32 = std.math.clamp(fit, MIN_FIT_SCALE, 1.0);
    const treeW = TREE_W * s;
    const treeH = TREE_H * s;
    const overflowX = @max(0, treeW - contentW);
    const overflowY = @max(0, treeH - contentH);
    const scrollable = overflowX > 0 or overflowY > 0;

    const mouse = input.pointerPos();
    const inContent = rl.checkCollisionPointRec(mouse, rl.Rectangle.init(contentX, contentY, contentW, contentH));

    // Wheel or right stick (vertical; shift or horizontal wheel for X) and
    // left-drag panning.
    if (scrollable) {
        const wheel = input.scrollV();
        const shift = rl.isKeyDown(rl.KeyboardKey.left_shift) or rl.isKeyDown(rl.KeyboardKey.right_shift);
        if (inContent or input.gamepadActive()) {
            if (shift) scrollX -= wheel.y * 40 else scrollY -= wheel.y * 40;
            scrollX -= wheel.x * 40;
        }
        if (inContent and input.confirmPressed()) {
            dragging = true;
            dragMoved = 0;
            lastMouse = mouse;
        }
        if (dragging) {
            if (input.confirmDown()) {
                const dx = mouse.x - lastMouse.x;
                const dy = mouse.y - lastMouse.y;
                dragMoved += @abs(dx) + @abs(dy);
                scrollX -= dx;
                scrollY -= dy;
                lastMouse = mouse;
            } else dragging = false;
        }
    } else {
        dragging = false;
    }
    scrollX = std.math.clamp(scrollX, 0, overflowX);
    scrollY = std.math.clamp(scrollY, 0, overflowY);

    // Centre when it fits; otherwise anchor top-left and apply the scroll.
    const centerX = if (overflowX > 0) contentX + treeW / 2 - scrollX else panelX + panelW / 2;
    const topY = if (overflowY > 0) contentY - scrollY else contentY + (contentH - treeH) / 2;
    const nodeW = NODE_W * s;
    const nodeH = NODE_H * s;

    ui_scale.beginScissor(contentX, contentY, contentW, contentH);

    // Prereq lines first (behind nodes)
    for (&upgrade_tree.NODES) |*node| {
        const to = nodePos(node, centerX, topY, s);
        const toC = rl.Vector2.init(to.x + nodeW / 2, to.y + nodeH / 2);
        for (node.prereqs) |pid| {
            const pnode = upgrade_tree.findNode(pid) orelse continue;
            const from = nodePos(pnode, centerX, topY, s);
            const fromC = rl.Vector2.init(from.x + nodeW / 2, from.y + nodeH / 2);

            const thick: f32 = (if (ctx.state.isPurchased(node.id)) @as(f32, 3) else 2) * s;
            const color = if (ctx.state.isPurchased(node.id))
                C.green
            else if (ctx.state.isPurchased(pid))
                C.sapphire
            else
                C.surface1;
            rl.drawLineEx(fromC, toC, thick, color);
        }
    }

    var action: TreeAction = .none;
    // A click that was really a pan shouldn't buy the node under the cursor.
    const clickOk = inContent and (!scrollable or dragMoved < 8);
    // Hovered node, remembered for the description tooltip drawn on top.
    var hoveredNode: ?*const upgrade_tree.Node = null;

    for (&upgrade_tree.NODES) |*node| {
        const pos = nodePos(node, centerX, topY, s);
        const rect = rl.Rectangle.init(pos.x, pos.y, nodeW, nodeH);
        const lvl = ctx.state.level(node.id);
        const purchased = lvl > 0;
        const maxed = node.isMaxed(lvl);
        const unlocked = ctx.state.isUnlocked(node);
        const cost = ctx.state.nextCost(node);
        const afford = ctx.resources.honey >= cost;
        const buyable = !maxed and unlocked;
        const style = styleFor(purchased, maxed, unlocked, afford);

        rl.drawRectangleRounded(rect, 0.22, 6, style.fill);
        rl.drawRectangleRoundedLinesEx(rect, 0.22, 6, style.borderThick * s, style.border);

        // Hover highlight on actionable nodes
        const hovered = inContent and rl.checkCollisionPointRec(mouse, rect);
        if (hovered) hoveredNode = node;
        if (buyable) input.registerHotspot(rect);
        if (buyable and afford and hovered) {
            var glow = C.blue;
            glow.a = 40;
            rl.drawRectangleRounded(rect, 0.22, 6, glow);
        }

        // Compact single-row body: effect icon | name (+Lv) | cost on the
        // right. Long localized names shrink a font step; if name + cost
        // still can't share the row, the cost drops to a second line.
        drawNodeIcon(ctx, node, pos.x + 16 * s, pos.y + nodeH / 2, s, unlocked);

        var nameBuf: [64]u8 = undefined;
        const localizedName = locale.nodeName(node.id, node.name);
        const nameZ = if (node.isRepeatable() and lvl > 0)
            std.fmt.bufPrintZ(&nameBuf, "{s} {s}{d}", .{ localizedName, locale.tr("Lv", "Nv"), lvl }) catch continue
        else
            std.fmt.bufPrintZ(&nameBuf, "{s}", .{localizedName}) catch continue;

        var cbuf: [32]u8 = undefined;
        const showCost = !style.showOwned and unlocked;
        const cstr = format.formatShort(cost, &cbuf);
        const textX: i32 = @intFromFloat(pos.x + 30 * s);
        const availW: i32 = @intFromFloat(nodeW - 38 * s);
        var nameSize = fs(15, s);
        var nameW = text.measure(nameZ, nameSize);
        if (nameW > availW) {
            nameSize = fs(12, s);
            nameW = text.measure(nameZ, nameSize);
        }
        const costSize = fs(14, s);
        const costW = if (showCost) text.measure(cstr, costSize) else 0;
        const costX = @as(i32, @intFromFloat(pos.x + nodeW - 8 * s)) - costW;
        const cy = @as(i32, @intFromFloat(pos.y + nodeH / 2));
        if (!showCost or nameW + costW + @as(i32, @intFromFloat(10 * s)) <= availW) {
            text.draw(nameZ, textX, cy - @divFloor(nameSize, 2), nameSize, style.nameColor);
            if (showCost) text.draw(cstr, costX, cy - @divFloor(costSize, 2), costSize, style.costColor);
        } else {
            text.draw(nameZ, textX, @intFromFloat(pos.y + 5 * s), nameSize, style.nameColor);
            text.draw(cstr, textX, @intFromFloat(pos.y + 24 * s), costSize, style.costColor);
        }

        if (buyable and afford and hovered and clickOk and input.confirmReleased()) {
            action = .{ .purchase = node.id };
        }
    }

    ui_scale.endScissor();

    // Description tooltip for the hovered node, above everything else.
    if (hoveredNode) |node| {
        const desc = locale.nodeDesc(node.id);
        var statusBuf: [96]u8 = undefined;
        const status = nodeStatus(ctx, node, ctx.state.level(node.id), &statusBuf);
        if (desc.len > 0) drawTooltip(desc, status, mouse, ctx.screenWidth, ctx.screenHeight);
    }

    // Scroll hint when clipped.
    if (scrollable) {
        const hint = locale.tr("scroll / drag to pan", "role / arraste para mover");
        const hw = text.measure(hint, 14);
        text.draw(hint, @as(i32, @intFromFloat(panelX + panelW - 18)) - hw, @as(i32, @intFromFloat(panelY + 24)), 14, C.overlay1);
    }

    // Close button
    const closeW: f32 = 140;
    const closeH: f32 = 44;
    const closeX = panelX + panelW - closeW - 14;
    const closeY = panelY + panelH - closeH - 14;
    if (widgets.button(rl.Rectangle.init(closeX, closeY, closeW, closeH), locale.tr("Close", "Fechar"))) {
        action = .close;
    }

    return action;
}

/// Small effect glyph on the node's left edge, from the shared primitive
/// icons plus the bee/flower sprites. Locked nodes draw it dimmed.
fn drawNodeIcon(ctx: TreeContext, node: *const upgrade_tree.Node, cx: f32, cy: f32, s: f32, unlocked: bool) void {
    const C = theme.CatppuccinMocha.Color;
    const dim = C.overlay0;
    switch (node.effect) {
        .honey_factor_mul => icons.drawHoneyDrop(cx, cy + 3 * s, 6 * s, if (unlocked) C.yellow else dim),
        .storage_add => {
            // Honey pot: body + lid.
            const col = if (unlocked) C.peach else dim;
            const w = 13 * s;
            rl.drawRectangleRounded(rl.Rectangle.init(cx - w / 2, cy - 3 * s, w, 9 * s), 0.5, 4, col);
            rl.drawRectangleRounded(rl.Rectangle.init(cx - w / 2 - 1.5 * s, cy - 7 * s, w + 3 * s, 4 * s), 0.6, 4, col);
        },
        .bee_unlock_worker, .bee_unlock_swift, .bee_unlock_efficient, .bee_unlock_gardener, .bee_lifespan_mul, .bulk_buy_tier => {
            const accent = switch (node.effect) {
                .bee_unlock_swift => C.blue,
                .bee_unlock_efficient => C.green,
                .bee_unlock_gardener => C.pink,
                .bee_lifespan_mul => C.teal,
                .bulk_buy_tier => C.yellow,
                else => C.text,
            };
            const size = 22 * s;
            rl.drawTexturePro(
                ctx.textures.bee,
                rl.Rectangle.init(0, 0, 32, 32),
                rl.Rectangle.init(cx - size / 2, cy - size / 2, size, size),
                rl.Vector2.init(0, 0),
                0,
                if (unlocked) accent else dim,
            );
        },
        .gardener_chance, .gardener_compost, .gardener_sweep, .growth_cd_sub, .growth_boost_unlock, .flower_growth_mul, .rot_chance_sub => icons.drawSprout(cx, cy + 7 * s, 14 * s, if (unlocked) C.green else dim),
        .grid_expand => {
            // Isometric tile diamond (both windings so culling can't hide it).
            const col = if (unlocked) C.lavender else dim;
            const rx = 9 * s;
            const ry = 6 * s;
            const top = rl.Vector2.init(cx, cy - ry);
            const left = rl.Vector2.init(cx - rx, cy);
            const right = rl.Vector2.init(cx + rx, cy);
            const bottom = rl.Vector2.init(cx, cy + ry);
            for ([_][3]rl.Vector2{ .{ top, left, right }, .{ bottom, right, left } }) |p| {
                rl.drawTriangle(p[0], p[1], p[2], col);
                rl.drawTriangle(p[2], p[1], p[0], col);
            }
        },
        .lab_aura, .aura_reach => icons.drawAura(cx, cy, 8 * s, if (unlocked) C.lavender else dim),
        .prestige_unlock => {
            // Crown dots, same motif as the prestige card.
            const col1 = if (unlocked) C.mauve else dim;
            const col2 = if (unlocked) C.pink else dim;
            rl.drawCircle(@intFromFloat(cx - 6 * s), @intFromFloat(cy + 2 * s), 3 * s, col1);
            rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy - 3 * s), 3.5 * s, col2);
            rl.drawCircle(@intFromFloat(cx + 6 * s), @intFromFloat(cy + 2 * s), 3 * s, col1);
        },
        .super_flower_unlock => {
            // Bloomed rose frame (state 4 of the 5-frame sheet).
            const size = 20 * s;
            rl.drawTexturePro(
                ctx.textures.getFlowerTexture(.rose),
                rl.Rectangle.init(128, 0, 32, 32),
                rl.Rectangle.init(cx - size / 2, cy - size / 2, size, size),
                rl.Vector2.init(0, 0),
                0,
                if (unlocked) rl.Color.white else dim,
            );
        },
    }
}

/// Multiplier label: two decimals while small, short-suffixed when large.
fn fmtMul(v: f32, buf: []u8) [:0]const u8 {
    if (v < 1000.0) return std.fmt.bufPrintZ(buf, "{d:.2}", .{v}) catch "?";
    return format.formatShort(v, buf);
}

/// Live "Now → Next" line for the tooltip: what the node currently gives and
/// what the next level would give, using the same formulas the game applies.
/// Null for one-shot nodes whose static description already says it all.
fn nodeStatus(ctx: TreeContext, node: *const upgrade_tree.Node, lvl: u16, buf: []u8) ?[:0]const u8 {
    const now = locale.tr("Now", "Agora");
    const nxt = locale.tr("Next", "Próx.");
    const maxed = node.isMaxed(lvl);
    switch (node.effect) {
        .honey_factor_mul => {
            // Only the repeatable Honey Boost accumulates a visible total.
            if (!node.isRepeatable()) return null;
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const cur = std.math.pow(f32, node.value, @floatFromInt(lvl));
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(cur, &b1), nxt, fmtMul(cur * node.value, &b2) }) catch null;
        },
        .gardener_chance => {
            const cur = bee_ai_system.gardenerChanceForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {d}%", .{ now, cur }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: {d}%  ·  {s}: {d}%", .{ now, cur, nxt, bee_ai_system.gardenerChanceForLevel(lvl + 1) }) catch null;
        },
        .growth_cd_sub => {
            const cur = ctx.resources.growthBoostMaxCooldown;
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {d:.0}s", .{ now, cur }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: {d:.0}s  ·  {s}: {d:.0}s", .{ now, cur, nxt, @max(2.0, cur - node.value) }) catch null;
        },
        .storage_add => {
            var b1: [24]u8 = undefined;
            const add = node.value * std.math.pow(f32, upgrade_tree.STORAGE_CAPACITY_GROWTH, @floatFromInt(lvl));
            return std.fmt.bufPrintZ(buf, "{s}: +{s} {s}", .{ nxt, format.formatShort(add, &b1), locale.tr("capacity", "de capacidade") }) catch null;
        },
        .lab_aura => {
            const cur = labs.auraMultiplierForLevel(lvl);
            return std.fmt.bufPrintZ(buf, "{s}: x{d:.2}  ·  {s}: x{d:.2}", .{ now, cur, nxt, labs.auraMultiplierForLevel(lvl + 1) }) catch null;
        },
        .aura_reach => {
            return std.fmt.bufPrintZ(buf, "{s}: {d:.0}  ·  {s}: {d:.0} {s}", .{ now, labs.auraReachForLevel(lvl), nxt, labs.auraReachForLevel(lvl + 1), locale.tr("tiles", "células") }) catch null;
        },
        .flower_growth_mul => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(flower_growth_system.growthMulForLevel(lvl), &b1), nxt, fmtMul(flower_growth_system.growthMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .bee_lifespan_mul => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(spawners.beeLifespanMulForLevel(lvl), &b1), nxt, fmtMul(spawners.beeLifespanMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .rot_chance_sub => {
            return std.fmt.bufPrintZ(buf, "{s}: {d}%  ·  {s}: {d}%", .{ now, lifespan_system.rotChanceForLevel(lvl), nxt, lifespan_system.rotChanceForLevel(lvl + 1) }) catch null;
        },
        .bulk_buy_tier => {
            if (lvl == 0) return std.fmt.bufPrintZ(buf, "{s}", .{locale.tr("Next: adds the x50 option", "Próx.: adiciona a opção x50")}) catch null;
            if (lvl == 1) return std.fmt.bufPrintZ(buf, "{s}", .{locale.tr("Next: adds the x100 option", "Próx.: adiciona a opção x100")}) catch null;
            return null;
        },
        else => return null,
    }
}

/// Word-wrapped description box near the cursor, clamped to the screen.
fn drawTooltip(desc: [:0]const u8, status: ?[:0]const u8, mouse: rl.Vector2, screenW: f32, screenH: f32) void {
    const C = theme.CatppuccinMocha.Color;
    const pad: f32 = 10;
    const size: i32 = 15;
    const lineH: f32 = 20;
    const tipW: f32 = 270;
    const maxTextW: i32 = @intFromFloat(tipW - pad * 2);

    // Wrap into at most 5 lines (descriptions are one sentence).
    var lineBufs: [5][96]u8 = undefined;
    var lines: [5][:0]const u8 = undefined;
    var lineCount: usize = 0;
    var cur: [96]u8 = undefined;
    var curLen: usize = 0;
    var it = std.mem.tokenizeScalar(u8, desc, ' ');
    while (it.next()) |word| {
        var cand: [96]u8 = undefined;
        var candLen: usize = 0;
        if (curLen > 0) {
            @memcpy(cand[0..curLen], cur[0..curLen]);
            cand[curLen] = ' ';
            candLen = curLen + 1;
        }
        if (candLen + word.len + 1 >= cand.len) break;
        @memcpy(cand[candLen .. candLen + word.len], word);
        candLen += word.len;
        cand[candLen] = 0;
        const candZ: [:0]const u8 = cand[0..candLen :0];
        if (curLen > 0 and text.measure(candZ, size) > maxTextW) {
            if (lineCount >= lines.len) break;
            @memcpy(lineBufs[lineCount][0..curLen], cur[0..curLen]);
            lineBufs[lineCount][curLen] = 0;
            lines[lineCount] = lineBufs[lineCount][0..curLen :0];
            lineCount += 1;
            @memcpy(cur[0..word.len], word);
            curLen = word.len;
        } else {
            @memcpy(cur[0..candLen], cand[0..candLen]);
            curLen = candLen;
        }
    }
    if (curLen > 0 and lineCount < lines.len) {
        @memcpy(lineBufs[lineCount][0..curLen], cur[0..curLen]);
        lineBufs[lineCount][curLen] = 0;
        lines[lineCount] = lineBufs[lineCount][0..curLen :0];
        lineCount += 1;
    }
    if (lineCount == 0) return;

    const statusRows: f32 = if (status != null) 1 else 0;
    const tipH = pad * 2 + lineH * (@as(f32, @floatFromInt(lineCount)) + statusRows) - 4;
    var x = mouse.x + 18;
    var y = mouse.y + 20;
    if (x + tipW > screenW - 6) x = mouse.x - tipW - 12;
    if (y + tipH > screenH - 6) y = mouse.y - tipH - 12;

    const rect = rl.Rectangle.init(x, y, tipW, tipH);
    rl.drawRectangleRounded(rect, 0.18, 6, rl.Color.init(17, 17, 27, 245));
    rl.drawRectangleRoundedLinesEx(rect, 0.18, 6, 1, C.surface2);
    for (lines[0..lineCount], 0..) |line, i| {
        text.draw(line, @intFromFloat(x + pad), @intFromFloat(y + pad + lineH * @as(f32, @floatFromInt(i))), size, C.subtext1);
    }
    if (status) |st| {
        text.draw(st, @intFromFloat(x + pad), @intFromFloat(y + pad + lineH * @as(f32, @floatFromInt(lineCount))), size, C.teal);
    }
}

