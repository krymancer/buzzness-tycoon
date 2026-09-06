//! Full-screen upgrade tree. It replaces the meadow while open (the meadow
//! keeps simulating underneath) rather than floating over a dimmed copy of
//! it, so the whole window is layout room. Nodes sit on a (col, row) lattice laid out by
//! dependency depth (see upgrade_tree.NODES); prerequisites are drawn as
//! orthogonal elbows — down out of the parent, across the gap between
//! rows, down into the child — so no link ever runs diagonally behind an
//! unrelated node. Nodes carry two rows: name, then cost / "affordable in"
//! countdown / level, with a progress strip for repeatables.

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
const clock = @import("../clock.zig");
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

const NODE_W: f32 = 148;
const NODE_H: f32 = 54;
const COL_SPACING: f32 = 160;
const ROW_SPACING: f32 = 72;
// Layout extents (cols -4..4, rows 0..6) at scale 1.
const MIN_COL: f32 = -4;
const MAX_COL: f32 = 4;
const MAX_ROW: f32 = 6;
const TREE_W: f32 = (MAX_COL - MIN_COL) * COL_SPACING + NODE_W;
const TREE_H: f32 = MAX_ROW * ROW_SPACING + NODE_H;
// Below this the tree stops shrinking to fit and scrolls instead.
const MIN_FIT_SCALE: f32 = 0.6;
// Above this the tree stops growing into spare room (text gets clumsy).
const MAX_FIT_SCALE: f32 = 1.3;

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

/// Purchase glow per node id: the node swells with a green ring that fades.
const FLASH_TIME: f32 = 0.5;
var nodeFlash: [64]f32 = @splat(0);

pub fn flashNode(id: upgrade_tree.NodeId) void {
    if (id < nodeFlash.len) nodeFlash[id] = FLASH_TIME;
}

fn withAlpha(c: rl.Color, a: u8) rl.Color {
    return rl.Color.init(c.r, c.g, c.b, a);
}

fn lerpColor(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const lerp = struct {
        fn f(x: u8, y: u8, k: f32) u8 {
            return @intFromFloat(@as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(y)) - @as(f32, @floatFromInt(x))) * k);
        }
    }.f;
    return rl.Color.init(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), 255);
}

pub const TreeContext = struct {
    screenWidth: f32,
    screenHeight: f32,
    state: *const upgrade_tree.State,
    resources: *const Resources,
    textures: *const Textures,
    /// PrestigeState.costMul() — scales displayed node prices.
    prestigeCostMul: f32,
    /// stats.prestigeCount — raises repeatable level caps.
    ascensions: u32,
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
    // Owned repeatable nodes keep a teal tint so "leveled" reads at a glance.
    if (afford) return .{
        .fill = C.surface0,
        .border = if (purchased) C.teal else C.blue,
        .borderThick = 3,
        .nameColor = C.text,
        .costColor = C.yellow,
    };
    // Reachable but too pricey: dimmed, not red — red reads as an error,
    // and the countdown next to the price already says "not yet".
    return .{
        .fill = C.surface0,
        .border = if (purchased) C.green else C.surface2,
        .borderThick = 2,
        .nameColor = C.subtext1,
        .costColor = C.overlay1,
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

/// Orthogonal connector from a parent's bottom edge to a child's top edge:
/// up to three segments (down, across, down). Same-column links are one
/// straight drop; the trunk under the root passes behind its own children.
const Path = struct {
    pts: [4]rl.Vector2,
    n: usize,

    fn length(self: *const @This()) f32 {
        var total: f32 = 0;
        for (1..self.n) |i| {
            total += @abs(self.pts[i].x - self.pts[i - 1].x) + @abs(self.pts[i].y - self.pts[i - 1].y);
        }
        return total;
    }

    /// Point at a fraction of the path's length (motes travel along it).
    fn at(self: *const @This(), frac: f32) rl.Vector2 {
        var remaining = self.length() * std.math.clamp(frac, 0, 1);
        for (1..self.n) |i| {
            const a = self.pts[i - 1];
            const b = self.pts[i];
            const seg = @abs(b.x - a.x) + @abs(b.y - a.y);
            if (remaining <= seg or i == self.n - 1) {
                const t = if (seg > 0) remaining / seg else 0;
                return rl.Vector2.init(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
            }
            remaining -= seg;
        }
        return self.pts[self.n - 1];
    }

    fn draw(self: *const @This(), thick: f32, color: rl.Color) void {
        for (1..self.n) |i| {
            rl.drawLineEx(self.pts[i - 1], self.pts[i], thick, color);
            // Round the joints so the elbows don't show notched corners.
            if (i < self.n - 1) rl.drawCircleV(self.pts[i], thick / 2, color);
        }
    }
};

fn routeFor(parent: *const upgrade_tree.Node, child: *const upgrade_tree.Node, centerX: f32, topY: f32, s: f32) Path {
    const nodeW = NODE_W * s;
    const nodeH = NODE_H * s;
    const p = nodePos(parent, centerX, topY, s);
    const c = nodePos(child, centerX, topY, s);
    const from = rl.Vector2.init(p.x + nodeW / 2, p.y + nodeH);
    const to = rl.Vector2.init(c.x + nodeW / 2, c.y);
    if (child.row <= parent.row) {
        // Not expected by the layout; fall back to a centre-to-centre line.
        return .{ .pts = .{ rl.Vector2.init(p.x + nodeW / 2, p.y + nodeH / 2), rl.Vector2.init(c.x + nodeW / 2, c.y + nodeH / 2), undefined, undefined }, .n = 2 };
    }
    if (parent.col == child.col) {
        return .{ .pts = .{ from, to, undefined, undefined }, .n = 2 };
    }
    // Across the gap right below the parent's row.
    const gapY = from.y + (ROW_SPACING - NODE_H) * s / 2;
    return .{ .pts = .{ from, rl.Vector2.init(from.x, gapY), rl.Vector2.init(to.x, gapY), to }, .n = 4 };
}

pub fn draw(ctx: TreeContext) TreeAction {
    const C = theme.CatppuccinMocha.Color;
    const now: f32 = @floatCast(clock.time());
    const dt = rl.getFrameTime();
    for (&nodeFlash) |*f| f.* = @max(0, f.* - dt);

    const panelW: f32 = ctx.screenWidth;
    const panelH: f32 = ctx.screenHeight;
    const panelX: f32 = 0;
    const panelY: f32 = 0;
    input.registerBlock(rl.Rectangle.init(panelX, panelY, panelW, panelH));

    // Deep solid bg so surface0 nodes read clearly on top; a thin accent
    // strip along the top breathes between blue and mauve like the
    // prestige screen's.
    rl.drawRectangle(0, 0, @intFromFloat(panelW), @intFromFloat(panelH), C.mantle);
    const breathe = 0.5 + 0.5 * @sin(now * 1.6);
    rl.drawRectangle(0, 0, @intFromFloat(panelW), 3, lerpColor(C.sapphire, C.mauve, breathe));

    const title = locale.tr("Upgrade Tree", "Árvore de Melhorias");
    const titleX = @as(i32, @intFromFloat(panelX + panelW / 2)) - @divFloor(text.measure(title, 32), 2);
    text.draw(title, titleX, @as(i32, @intFromFloat(panelY + 10)), 32, C.mauve);

    // Honey stash pill (helps gauge affordability), top-left.
    var hbuf: [32]u8 = undefined;
    const hstr = format.formatShort(ctx.resources.honey, &hbuf);
    const honeyLabel = rl.textFormat(locale.tr("%s honey", "%s de mel"), .{hstr.ptr});
    const honeyW: f32 = @floatFromInt(text.measure(honeyLabel, 19));
    const pill = rl.Rectangle.init(panelX + 16, panelY + 14, honeyW + 46, 36);
    rl.drawRectangleRounded(pill, 0.5, 8, C.surface0);
    rl.drawRectangleRoundedLinesEx(pill, 0.5, 8, 1, C.surface2);
    icons.drawHoneyDrop(pill.x + 18, pill.y + 22, 5.5, C.yellow);
    text.draw(honeyLabel, @intFromFloat(pill.x + 32), @intFromFloat(pill.y + 8), 19, C.yellow);

    // Progress pill ("14/27 owned"), top-right.
    const ownedLabel = rl.textFormat(locale.tr("%d/%d owned", "%d/%d obtidos"), .{ @as(c_int, @intCast(ctx.state.ownedCount())), @as(c_int, @intCast(upgrade_tree.NODE_COUNT)) });
    const ownedW: f32 = @floatFromInt(text.measure(ownedLabel, 19));
    const opill = rl.Rectangle.init(panelX + panelW - 16 - (ownedW + 28), panelY + 14, ownedW + 28, 36);
    rl.drawRectangleRounded(opill, 0.5, 8, C.surface0);
    rl.drawRectangleRoundedLinesEx(opill, 0.5, 8, 1, C.surface2);
    text.draw(ownedLabel, @intFromFloat(opill.x + 14), @intFromFloat(opill.y + 8), 19, C.subtext1);

    // Content area between the title row and the legend/close row.
    const contentX = panelX + 20;
    const contentY = panelY + 60;
    const contentW = panelW - 40;
    const contentH = panelH - 60 - 78;

    // Auto-fit: shrink the layout so the whole tree shows whenever it can
    // (big UI scale => small logical panel); below MIN_FIT_SCALE, scroll.
    const fit = @min(contentW / TREE_W, contentH / TREE_H);
    const s: f32 = std.math.clamp(fit, MIN_FIT_SCALE, MAX_FIT_SCALE);
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
    // centerX is where column 0 sits, so centre the column span's midpoint
    // in case the span is ever asymmetric.
    const midCol = (MIN_COL + MAX_COL) / 2;
    const centerX = if (overflowX > 0)
        contentX - scrollX - MIN_COL * COL_SPACING * s + NODE_W * s / 2
    else
        panelX + panelW / 2 - midCol * COL_SPACING * s;
    const topY = if (overflowY > 0) contentY - scrollY else contentY + (contentH - treeH) / 2;
    const nodeW = NODE_W * s;
    const nodeH = NODE_H * s;

    // Hovered node first, so a locked node's missing prerequisites can be
    // highlighted while its own body draws.
    var hoveredNode: ?*const upgrade_tree.Node = null;
    if (inContent) {
        for (&upgrade_tree.NODES) |*node| {
            const p = nodePos(node, centerX, topY, s);
            if (rl.checkCollisionPointRec(mouse, rl.Rectangle.init(p.x, p.y, nodeW, nodeH))) hoveredNode = node;
        }
    }
    const cheapest = ctx.state.cheapestBuyable(ctx.prestigeCostMul, ctx.ascensions);

    ui_scale.beginScissor(contentX, contentY, contentW, contentH);

    // Prereq connectors first (behind nodes), in three passes so a shared
    // trunk segment shows its most advanced state on top: dormant links,
    // then open (parent owned) links, then owned links.
    for (0..3) |pass| {
        for (&upgrade_tree.NODES) |*node| {
            const childOwned = ctx.state.isPurchased(node.id);
            for (node.prereqs) |p| {
                const pnode = upgrade_tree.findNode(p.id) orelse continue;
                const parentMet = ctx.state.prereqMet(p);
                const cls: usize = if (childOwned) 2 else if (parentMet) 1 else 0;
                if (cls != pass) continue;
                const path = routeFor(pnode, node, centerX, topY, s);
                const thick: f32 = (if (childOwned) @as(f32, 3) else 2) * s;
                const color = if (childOwned) C.green else if (parentMet) C.sapphire else C.surface1;
                path.draw(thick, color);

                // Sap flowing toward a reachable-but-unbought node: two motes
                // travel the line so open branches read as alive.
                if (parentMet and !childOwned and ctx.state.isUnlocked(node)) {
                    for (0..2) |k| {
                        const frac = @mod(now * 0.35 + @as(f32, @floatFromInt(k)) * 0.5 + @as(f32, @floatFromInt(node.id)) * 0.13, 1.0);
                        const pt = path.at(frac);
                        rl.drawCircleV(pt, 4 * s, withAlpha(C.sky, 70));
                        rl.drawCircleV(pt, 2.2 * s, C.sky);
                    }
                }
            }
        }
    }

    var action: TreeAction = .none;
    // A click that was really a pan shouldn't buy the node under the cursor.
    const clickOk = inContent and (!scrollable or dragMoved < 8);

    for (&upgrade_tree.NODES) |*node| {
        const basePos = nodePos(node, centerX, topY, s);
        const hitRect = rl.Rectangle.init(basePos.x, basePos.y, nodeW, nodeH);
        const lvl = ctx.state.level(node.id);
        const purchased = lvl > 0;
        const maxed = node.isMaxed(lvl, ctx.ascensions);
        const unlocked = ctx.state.isUnlocked(node);
        const cost = ctx.state.nextCost(node, ctx.prestigeCostMul);
        const afford = ctx.resources.honey >= cost;
        const buyable = !maxed and unlocked;
        var style = styleFor(purchased, maxed, unlocked, afford);

        // Hovering a locked node points at what it's waiting on.
        if (hoveredNode) |h| {
            if (h != node and !ctx.state.isUnlocked(h)) {
                for (h.prereqs) |p| {
                    if (p.id == node.id and !ctx.state.prereqMet(p)) {
                        style.border = C.peach;
                        style.borderThick = 3;
                    }
                }
            }
        }

        // Actionable nodes lift slightly under the cursor.
        const hovered = hoveredNode == node;
        const lift: f32 = if (hovered and buyable) 2 * s else 0;
        const pos = rl.Vector2.init(basePos.x, basePos.y - lift);
        const rect = rl.Rectangle.init(pos.x, pos.y, nodeW, nodeH);
        if (buyable) input.registerHotspot(hitRect);

        // Affordable nodes carry a soft pulsing halo so "you can buy this"
        // reads without hunting for blue borders.
        if (buyable and afford) {
            const pulse = 0.5 + 0.5 * @sin(now * 3.0 + @as(f32, @floatFromInt(node.id)) * 0.7);
            const spread = (2 + 3 * pulse) * s;
            const halo = rl.Rectangle.init(rect.x - spread, rect.y - spread, rect.width + 2 * spread, rect.height + 2 * spread);
            rl.drawRectangleRounded(halo, 0.3, 6, withAlpha(if (purchased) C.teal else C.blue, @intFromFloat(18 + 30 * pulse)));
        }

        rl.drawRectangleRounded(rect, 0.2, 6, style.fill);
        rl.drawRectangleRoundedLinesEx(rect, 0.2, 6, style.borderThick * s, style.border);

        if (buyable and afford and hovered) {
            rl.drawRectangleRounded(rect, 0.2, 6, withAlpha(C.blue, 40));
        }

        // Purchase glow: a green ring bursts outward and fades.
        const flash = if (node.id < nodeFlash.len) nodeFlash[node.id] else 0;
        if (flash > 0) {
            const t = flash / FLASH_TIME;
            const spread = (14 * (1 - t) + 2) * s;
            const ring = rl.Rectangle.init(rect.x - spread, rect.y - spread, rect.width + 2 * spread, rect.height + 2 * spread);
            rl.drawRectangleRounded(rect, 0.2, 6, withAlpha(C.green, @intFromFloat(90 * t)));
            rl.drawRectangleRoundedLinesEx(ring, 0.3, 6, 2 * s, withAlpha(C.green, @intFromFloat(220 * t)));
        }

        // Body: effect icon on the left; row 1 the name, row 2 the price
        // (or Owned / Max), an "in 12s" countdown when it's out of reach,
        // and the level on the right for repeatables.
        drawNodeIcon(ctx, node, pos.x + 16 * s, pos.y + nodeH / 2 - 2 * s, s, unlocked);

        const textX: i32 = @intFromFloat(pos.x + 30 * s);
        const rightX: i32 = @intFromFloat(pos.x + nodeW - 8 * s);
        const availW: i32 = rightX - textX;

        var nameBuf: [64]u8 = undefined;
        const nameZ = std.fmt.bufPrintZ(&nameBuf, "{s}", .{locale.nodeName(node.id, node.name)}) catch continue;
        var nameSize = fs(15, s);
        if (text.measure(nameZ, nameSize) > availW) nameSize = fs(12, s);
        text.draw(nameZ, textX, @intFromFloat(pos.y + 7 * s), nameSize, style.nameColor);

        const row2Y: i32 = @intFromFloat(pos.y + 29 * s);
        const smallSize = fs(13, s);
        var cx: i32 = textX;
        if (style.showOwned) {
            const owned = if (node.isRepeatable()) locale.tr("Max", "Máx.") else locale.tr("Owned", "Obtido");
            text.draw(owned, cx, row2Y, smallSize, C.green);
            cx += text.measure(owned, smallSize);
        } else {
            var cbuf: [32]u8 = undefined;
            const cstr = format.formatShort(cost, &cbuf);
            text.draw(cstr, cx, row2Y, smallSize, style.costColor);
            cx += text.measure(cstr, smallSize);
            if (unlocked and !afford) {
                if (format.secondsUntil(cost, ctx.resources.honey, ctx.resources.honeyPerSec)) |secs| {
                    var ebuf: [16]u8 = undefined;
                    if (format.formatEta(secs, &ebuf)) |eta| {
                        var lbuf: [32]u8 = undefined;
                        const etaLabel = std.fmt.bufPrintZ(&lbuf, "{s} {s}", .{ locale.tr("in", "em"), eta }) catch eta;
                        cx += @intFromFloat(6 * s);
                        text.draw(etaLabel, cx, row2Y, smallSize, C.peach);
                        cx += text.measure(etaLabel, smallSize);
                    }
                }
            }
        }

        if (node.repeat) |r| {
            if (unlocked or purchased) {
                const cap = r.capAt(ctx.ascensions);
                var lbuf: [24]u8 = undefined;
                const lvlLabel = std.fmt.bufPrintZ(&lbuf, "{s} {d}/{d}", .{ locale.tr("Lv", "Nv"), lvl, cap }) catch "";
                const lw = text.measure(lvlLabel, smallSize);
                // Only if it doesn't collide with the price/countdown.
                if (rightX - lw > cx + @as(i32, @intFromFloat(6 * s))) {
                    text.draw(lvlLabel, rightX - lw, row2Y, smallSize, if (maxed) C.green else C.subtext0);
                }
                // Level strip along the bottom edge.
                const stripX = pos.x + 6 * s;
                const stripW = nodeW - 12 * s;
                const stripY = pos.y + nodeH - 6 * s;
                rl.drawRectangleRounded(rl.Rectangle.init(stripX, stripY, stripW, 3 * s), 0.5, 4, C.surface1);
                const frac = if (cap > 0) @as(f32, @floatFromInt(@min(lvl, cap))) / @as(f32, @floatFromInt(cap)) else 0;
                if (frac > 0) {
                    rl.drawRectangleRounded(rl.Rectangle.init(stripX, stripY, stripW * frac, 3 * s), 0.5, 4, if (maxed) C.green else C.teal);
                }
            }
        }

        // "next" tag on the cheapest buyable node: the natural next step
        // when nothing glows yet.
        if (cheapest == node.id and buyable) {
            const tagLabel = locale.tr("next", "próx.");
            const tagSize = fs(11, s);
            const tw: f32 = @floatFromInt(text.measure(tagLabel, tagSize));
            const tag = rl.Rectangle.init(rect.x + rect.width - tw - 18 * s, rect.y - 8 * s, tw + 12 * s, 16 * s);
            rl.drawRectangleRounded(tag, 0.5, 6, C.yellow);
            text.draw(tagLabel, @intFromFloat(tag.x + 6 * s), @intFromFloat(tag.y + 1.5 * s), tagSize, C.base);
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
        var needsBuf: [128]u8 = undefined;
        const needs = missingPrereqs(ctx, node, &needsBuf);
        if (desc.len > 0) drawTooltip(desc, status, needs, mouse, ctx.screenWidth, ctx.screenHeight);
    }

    // Close button
    const closeW: f32 = 140;
    const closeH: f32 = 44;
    const closeX = panelX + panelW - closeW - 14;
    const closeY = panelY + panelH - closeH - 14;
    if (widgets.button(rl.Rectangle.init(closeX, closeY, closeW, closeH), locale.tr("Close", "Fechar"))) {
        action = .close;
    }

    // Scroll hint when clipped, bottom-left, level with the close button.
    if (scrollable) {
        const hint = locale.tr("scroll / drag to pan", "role / arraste para mover");
        text.draw(hint, @intFromFloat(panelX + 18), @intFromFloat(closeY + 14), 14, C.overlay1);
    }

    return action;
}

/// "Needs: Honey Doubler Lv3, Gardener Bee" for a locked node; null when
/// every prerequisite is met.
fn missingPrereqs(ctx: TreeContext, node: *const upgrade_tree.Node, buf: []u8) ?[:0]const u8 {
    if (ctx.state.isUnlocked(node)) return null;
    var w: std.Io.Writer = .fixed(buf[0 .. buf.len - 1]);
    w.print("{s}: ", .{locale.tr("Needs", "Requer")}) catch return null;
    var first = true;
    for (node.prereqs) |p| {
        if (ctx.state.prereqMet(p)) continue;
        const pnode = upgrade_tree.findNode(p.id) orelse continue;
        if (!first) w.writeAll(", ") catch return null;
        first = false;
        w.writeAll(locale.nodeName(pnode.id, pnode.name)) catch return null;
        if (p.level > 1) w.print(" {s}{d}", .{ locale.tr("Lv", "Nv"), p.level }) catch return null;
    }
    const n = w.end;
    buf[n] = 0;
    return buf[0..n :0];
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
        .bee_unlock_worker, .bee_unlock_swift, .bee_unlock_efficient, .bee_unlock_gardener, .bee_lifespan_mul, .bulk_buy_tier, .bee_speed_mul, .bee_carry_add, .bee_training => {
            const accent = switch (node.effect) {
                .bee_unlock_swift => C.blue,
                .bee_unlock_efficient => C.green,
                .bee_unlock_gardener => C.pink,
                .bee_lifespan_mul => C.teal,
                .bulk_buy_tier => C.yellow,
                .bee_speed_mul => C.sky,
                .bee_carry_add => C.peach,
                // Drills wear their type's colour so the column reads as
                // "one per bee".
                .bee_training => switch (upgrade_tree.trainingType(node.id) orelse 0) {
                    1 => C.blue,
                    2 => C.green,
                    3 => C.pink,
                    else => C.text,
                },
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
        .gardener_chance, .gardener_compost, .gardener_sow, .growth_cd_sub, .growth_boost_unlock, .flower_growth_mul, .rot_chance_sub => icons.drawSprout(cx, cy + 7 * s, 14 * s, if (unlocked) C.green else dim),
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
        .night_penalty_sub => {
            // Full moon with craters, echoing the night sky's moon.
            const col = if (unlocked) C.lavender else dim;
            const crater = if (unlocked) C.overlay1 else C.surface1;
            rl.drawCircle(@intFromFloat(cx), @intFromFloat(cy), 7 * s, col);
            rl.drawCircle(@intFromFloat(cx - 2 * s), @intFromFloat(cy - 1.5 * s), 1.5 * s, crater);
            rl.drawCircle(@intFromFloat(cx + 2 * s), @intFromFloat(cy + 1.5 * s), 2 * s, crater);
            rl.drawCircle(@intFromFloat(cx + 0.5 * s), @intFromFloat(cy - 4 * s), 1.2 * s, crater);
        },
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

/// "Level cap reached — Ascend raises it" hint for maxed repeatables whose
/// cap grows with ascensions; a plain cap notice for the rest.
fn capHint(node: *const upgrade_tree.Node) [:0]const u8 {
    const r = node.repeat orelse return "";
    if (r.per_ascension > 0) return locale.tr("Ascend to raise the cap", "Ascenda para aumentar o limite");
    return locale.tr("Max level", "Nível máximo");
}

/// Live "Now → Next" line for the tooltip: what the node currently gives and
/// what the next level would give, using the same formulas the game applies.
/// Null for one-shot nodes whose static description already says it all.
fn nodeStatus(ctx: TreeContext, node: *const upgrade_tree.Node, lvl: u16, buf: []u8) ?[:0]const u8 {
    const now = locale.tr("Now", "Agora");
    const nxt = locale.tr("Next", "Próx.");
    const maxed = node.isMaxed(lvl, ctx.ascensions);
    switch (node.effect) {
        .honey_factor_mul => {
            // Both honey nodes are repeatable and accumulate a visible total.
            if (!node.isRepeatable()) return null;
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const cur = std.math.pow(f32, node.value, @floatFromInt(lvl));
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}", .{ now, fmtMul(cur, &b1), capHint(node) }) catch null;
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
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}", .{capHint(node)}) catch null;
            const add = node.value * std.math.pow(f32, upgrade_tree.STORAGE_CAPACITY_GROWTH, @floatFromInt(lvl));
            return std.fmt.bufPrintZ(buf, "{s}: +{s} {s}", .{ nxt, format.formatShort(add, &b1), locale.tr("capacity", "de capacidade") }) catch null;
        },
        .lab_aura => {
            const cur = labs.auraMultiplierForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{d:.2}  ·  {s}", .{ now, cur, capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{d:.2}  ·  {s}: x{d:.2}", .{ now, cur, nxt, labs.auraMultiplierForLevel(lvl + 1) }) catch null;
        },
        .aura_reach => {
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {d:.0} {s}  ·  {s}", .{ now, labs.auraReachForLevel(lvl), locale.tr("tiles", "células"), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: {d:.0}  ·  {s}: {d:.0} {s}", .{ now, labs.auraReachForLevel(lvl), nxt, labs.auraReachForLevel(lvl + 1), locale.tr("tiles", "células") }) catch null;
        },
        .flower_growth_mul => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}", .{ now, fmtMul(flower_growth_system.growthMulForLevel(lvl), &b1), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(flower_growth_system.growthMulForLevel(lvl), &b1), nxt, fmtMul(flower_growth_system.growthMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .bee_lifespan_mul => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}", .{ now, fmtMul(spawners.beeLifespanMulForLevel(lvl), &b1), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(spawners.beeLifespanMulForLevel(lvl), &b1), nxt, fmtMul(spawners.beeLifespanMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .rot_chance_sub => {
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {d}%  ·  {s}", .{ now, lifespan_system.rotChanceForLevel(lvl), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: {d}%  ·  {s}: {d}%", .{ now, lifespan_system.rotChanceForLevel(lvl), nxt, lifespan_system.rotChanceForLevel(lvl + 1) }) catch null;
        },
        .night_penalty_sub => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const suffix = locale.tr("honey at night", "de mel à noite");
            const cur = bee_ai_system.nightHoneyMulForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s} {s}", .{ now, fmtMul(cur, &b1), suffix }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s} {s}", .{ now, fmtMul(cur, &b1), nxt, fmtMul(bee_ai_system.nightHoneyMulForLevel(lvl + 1), &b2), suffix }) catch null;
        },
        .bee_speed_mul => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const cur = bee_ai_system.beeSpeedMulForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}", .{ now, fmtMul(cur, &b1), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(cur, &b1), nxt, fmtMul(bee_ai_system.beeSpeedMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .bee_training => {
            var b1: [24]u8 = undefined;
            var b2: [24]u8 = undefined;
            const cur = bee_ai_system.trainingMulForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}", .{ now, fmtMul(cur, &b1), capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: x{s}  ·  {s}: x{s}", .{ now, fmtMul(cur, &b1), nxt, fmtMul(bee_ai_system.trainingMulForLevel(lvl + 1), &b2) }) catch null;
        },
        .bee_carry_add => {
            const per = locale.tr("flowers per trip", "flores por viagem");
            const cur = bee_ai_system.bagCapacityForLevel(lvl);
            if (maxed) return std.fmt.bufPrintZ(buf, "{s}: {d} {s}  ·  {s}", .{ now, cur, per, capHint(node) }) catch null;
            return std.fmt.bufPrintZ(buf, "{s}: {d}  ·  {s}: {d} {s}", .{ now, cur, nxt, bee_ai_system.bagCapacityForLevel(lvl + 1), per }) catch null;
        },
        .bulk_buy_tier => {
            const hud = @import("action_hud.zig");
            const nextIdx = hud.BASE_QTY_COUNT + @as(usize, lvl);
            if (nextIdx >= hud.BUY_QTYS.len) return null;
            return std.fmt.bufPrintZ(buf, "{s}: {s} x{d}", .{ nxt, locale.tr("adds the option", "adiciona a opção"), hud.BUY_QTYS[nextIdx] }) catch null;
        },
        else => return null,
    }
}

/// Word-wrapped description box near the cursor, clamped to the screen.
/// `status` is the live Now/Next line, `needs` the unmet-prerequisite line.
fn drawTooltip(desc: [:0]const u8, status: ?[:0]const u8, needs: ?[:0]const u8, mouse: rl.Vector2, screenW: f32, screenH: f32) void {
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

    const extraRows: f32 = (if (status != null) @as(f32, 1) else 0) + (if (needs != null) @as(f32, 1) else 0);
    const tipH = pad * 2 + lineH * (@as(f32, @floatFromInt(lineCount)) + extraRows) - 4;
    var x = mouse.x + 18;
    var y = mouse.y + 20;
    if (x + tipW > screenW - 6) x = mouse.x - tipW - 12;
    if (y + tipH > screenH - 6) y = mouse.y - tipH - 12;

    const rect = rl.Rectangle.init(x, y, tipW, tipH);
    rl.drawRectangleRounded(rect, 0.18, 6, rl.Color.init(17, 17, 27, 245));
    rl.drawRectangleRoundedLinesEx(rect, 0.18, 6, 1, C.surface2);
    var row: f32 = 0;
    for (lines[0..lineCount]) |line| {
        text.draw(line, @intFromFloat(x + pad), @intFromFloat(y + pad + lineH * row), size, C.subtext1);
        row += 1;
    }
    if (status) |st| {
        text.draw(st, @intFromFloat(x + pad), @intFromFloat(y + pad + lineH * row), size, C.teal);
        row += 1;
    }
    if (needs) |nd| {
        text.draw(nd, @intFromFloat(x + pad), @intFromFloat(y + pad + lineH * row), size, C.peach);
    }
}
