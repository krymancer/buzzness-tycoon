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

const NODE_W: f32 = 240;
const NODE_H: f32 = 60;
const COL_SPACING: f32 = 260;
const ROW_SPACING: f32 = 84;
// Layout extents (cols -4..4, rows 0..6) at scale 1.
const MIN_COL: f32 = -4;
const MAX_COL: f32 = 4;
const MAX_ROW: f32 = 6;
const TREE_W: f32 = (MAX_COL - MIN_COL) * COL_SPACING + NODE_W;
const TREE_H: f32 = MAX_ROW * ROW_SPACING + NODE_H;
// The tree is a map: drag (or right stick / WASD) to pan, wheel (or
// triggers / +-) to zoom about the cursor, "Fit" or Home to reset. It never
// opens at a readable scale; Fit provides an optional overview.
const ZOOM_MIN: f32 = 0.45;
const ZOOM_MAX: f32 = 2.2;
/// Fit leaves this much of the content area as margin around the tree.
const FIT_MARGIN: f32 = 0.92;
/// Panning can't push the tree further than this many px from the edge, so
/// it can always be dragged back.
const KEEP_VISIBLE: f32 = 140;

var zoom: f32 = 1;
// Tree-centre offset from the content centre, logical px.
var panX: f32 = 0;
var panY: f32 = 0;
var viewFitted: bool = false;
var selectedId: upgrade_tree.NodeId = 20;
var pendingFocus: ?upgrade_tree.NodeId = null;
var pressedNode: ?upgrade_tree.NodeId = null;
var dragging: bool = false;
var dragMoved: f32 = 0;
var lastMouse: rl.Vector2 = .{ .x = 0, .y = 0 };

/// End a gesture when reopening; retain the player's view and selection.
pub fn resetView() void {
    dragging = false;
    pressedNode = null;
}

pub fn focusNode(id: upgrade_tree.NodeId) void {
    selectedId = id;
    pendingFocus = id;
    dragging = false;
}

/// Dev: BT_TREE_ZOOM=<factor> opens the tree at that zoom instead of the
/// fit (screenshots of the zoomed-in map). Set by game.zig at startup.
pub var devOpenZoom: ?f32 = null;

fn fitView(contentW: f32, contentH: f32) void {
    zoom = std.math.clamp(@min(contentW / TREE_W, contentH / TREE_H) * FIT_MARGIN, ZOOM_MIN, ZOOM_MAX);
    if (devOpenZoom) |z| {
        zoom = std.math.clamp(z, ZOOM_MIN, ZOOM_MAX);
        devOpenZoom = null;
    }
    panX = 0;
    panY = 0;
    viewFitted = true;
}

/// Change the zoom while keeping the tree point under `anchor` (screen px)
/// where it is, so wheel-zoom feels anchored to the cursor.
fn zoomAt(anchor: rl.Vector2, newZoom: f32, cx: f32, cy: f32) void {
    const z1 = std.math.clamp(newZoom, ZOOM_MIN, ZOOM_MAX);
    if (z1 == zoom) return;
    const tl0 = rl.Vector2.init(cx + panX - TREE_W * zoom / 2, cy + panY - TREE_H * zoom / 2);
    const ux = (anchor.x - tl0.x) / zoom;
    const uy = (anchor.y - tl0.y) / zoom;
    const tl1 = rl.Vector2.init(anchor.x - ux * z1, anchor.y - uy * z1);
    zoom = z1;
    panX = tl1.x + TREE_W * z1 / 2 - cx;
    panY = tl1.y + TREE_H * z1 / 2 - cy;
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

/// Node top-left from the tree's top-left corner `tl` at scale `s`.
fn nodePos(node: *const upgrade_tree.Node, tl: rl.Vector2, s: f32) rl.Vector2 {
    const x = tl.x + (@as(f32, @floatFromInt(node.col)) - MIN_COL) * COL_SPACING * s;
    const y = tl.y + @as(f32, @floatFromInt(node.row)) * ROW_SPACING * s;
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

fn routeFor(parent: *const upgrade_tree.Node, child: *const upgrade_tree.Node, tl: rl.Vector2, s: f32) Path {
    const nodeW = NODE_W * s;
    const nodeH = NODE_H * s;
    const p = nodePos(parent, tl, s);
    const c = nodePos(child, tl, s);
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
    const dt = rl.getFrameTime();
    for (&nodeFlash) |*f| f.* = @max(0, f.* - dt);
    const W = ctx.screenWidth;
    const H = ctx.screenHeight;
    const mouse = input.pointerPos();
    input.registerBlock(rl.Rectangle.init(0, 0, W, H));
    rl.drawRectangle(0, 0, @intFromFloat(W), @intFromFloat(H), C.mantle);
    text.draw(locale.tr("Upgrade Tree", "Árvore de Melhorias"), 18, 12, 28, C.mauve);
    var hb: [32]u8 = undefined;
    const honey = format.formatShort(ctx.resources.honey, &hb);
    const summary = rl.textFormat(locale.tr("%s honey · %d/%d owned", "%s mel · %d/%d obtidos"), .{ honey.ptr, @as(c_int, @intCast(ctx.state.ownedCount())), @as(c_int, @intCast(upgrade_tree.NODE_COUNT)) });
    text.draw(summary, @intFromFloat(W - @as(f32, @floatFromInt(text.measure(summary, 17))) - 18), 19, 17, C.yellow);

    // Named shortcuts pan to a branch without hiding dependencies.
    const branches = [_][:0]const u8{ locale.tr("Bees", "Abelhas"), locale.tr("Honey", "Mel"), locale.tr("Meadow", "Campina"), locale.tr("Colony", "Colônia"), locale.tr("Labs", "Labs") };
    const targets = [_]upgrade_tree.NodeId{ 4, 1, 13, 30, upgrade_tree.AURA_ID };
    const bw = @min(132, (W - 36) / 5);
    for (branches, targets, 0..) |label, id, i| {
        if (widgets.segment(rl.Rectangle.init(18 + @as(f32, @floatFromInt(i)) * bw, 52, bw - 6, 34), label, selectedId == id)) focusNode(id);
    }

    const side = W >= 1100;
    const detailsW: f32 = if (side) 320 else W - 36;
    const detailsH: f32 = if (side) H - 164 else 202;
    const content = rl.Rectangle.init(18, 102, W - 36 - (if (side) @as(f32, 338) else 0), H - 164 - (if (side) @as(f32, 0) else detailsH + 12));
    const details = rl.Rectangle.init(if (side) W - detailsW - 18 else 18, if (side) 102 else content.y + content.height + 12, detailsW, detailsH);
    const ccx = content.x + content.width / 2;
    const ccy = content.y + content.height / 2;
    if (!viewFitted) {
        zoom = devOpenZoom orelse 1.1;
        devOpenZoom = null;
        viewFitted = true;
        if (pendingFocus == null) pendingFocus = selectedId;
    }
    if (pendingFocus) |id| {
        const node = upgrade_tree.findNode(id) orelse &upgrade_tree.NODES[0];
        zoom = @max(1.0, zoom);
        panX = TREE_W * zoom / 2 - ((@as(f32, @floatFromInt(node.col)) - MIN_COL) * COL_SPACING + NODE_W / 2) * zoom;
        panY = TREE_H * zoom / 2 - (@as(f32, @floatFromInt(node.row)) * ROW_SPACING + NODE_H / 2) * zoom;
        pendingFocus = null;
    }
    const inContent = rl.checkCollisionPointRec(mouse, content);
    const wheel = rl.getMouseWheelMoveV().y;
    if (inContent and wheel != 0) zoomAt(mouse, zoom * std.math.pow(f32, 1.12, wheel), ccx, ccy);
    const zaxis = input.zoomAxis();
    if (zaxis != 0) zoomAt(rl.Vector2.init(ccx, ccy), zoom * std.math.pow(f32, 2.0, zaxis * dt), ccx, ccy);
    if (inContent and input.confirmPressed()) {
        dragging = true;
        dragMoved = 0;
        lastMouse = mouse;
        pressedNode = null;
    }
    if (dragging and input.confirmDown()) {
        const dx = mouse.x - lastMouse.x;
        const dy = mouse.y - lastMouse.y;
        dragMoved += @abs(dx) + @abs(dy);
        panX += dx;
        panY += dy;
        lastMouse = mouse;
    }
    const keyPan = input.cameraPan();
    panX -= keyPan.x;
    panY -= keyPan.y;
    if (rl.isKeyPressed(.home)) fitView(content.width, content.height);
    const s = zoom;
    panX = std.math.clamp(panX, -@max(0, TREE_W * s / 2 + content.width / 2 - KEEP_VISIBLE), @max(0, TREE_W * s / 2 + content.width / 2 - KEEP_VISIBLE));
    panY = std.math.clamp(panY, -@max(0, TREE_H * s / 2 + content.height / 2 - KEEP_VISIBLE), @max(0, TREE_H * s / 2 + content.height / 2 - KEEP_VISIBLE));
    const tl = rl.Vector2.init(ccx + panX - TREE_W * s / 2, ccy + panY - TREE_H * s / 2);
    ui_scale.beginScissor(content.x, content.y, content.width, content.height);
    for (&upgrade_tree.NODES) |*node| {
        for (node.prereqs) |prereq| {
            const parent = upgrade_tree.findNode(prereq.id) orelse continue;
            const path = routeFor(parent, node, tl, s);
            path.draw(2 * s, if (node.id == selectedId) C.peach else if (ctx.state.prereqMet(prereq)) C.sapphire else C.surface1);
        }
    }
    const cheapest = ctx.state.cheapestBuyable(ctx.prestigeCostMul, ctx.ascensions);
    for (&upgrade_tree.NODES) |*node| {
        const pos = nodePos(node, tl, s);
        const rect = rl.Rectangle.init(pos.x, pos.y, NODE_W * s, NODE_H * s);
        if (!rl.checkCollisionRecs(rect, content)) continue;
        const fullyVisible = rect.x >= content.x and rect.y >= content.y and rect.x + rect.width <= content.x + content.width and rect.y + rect.height <= content.y + content.height;
        if (fullyVisible) input.registerHotspot(rect); // Locked nodes are inspectable, too.
        const hovered = inContent and rl.checkCollisionPointRec(mouse, rect);
        if (hovered and input.confirmPressed()) pressedNode = node.id;
        if (hovered and dragging and dragMoved < 8 and pressedNode == node.id and input.confirmReleased()) selectedId = node.id;
        const lvl = ctx.state.level(node.id);
        const maxed = node.isMaxed(lvl, ctx.ascensions);
        const unlocked = ctx.state.isUnlocked(node);
        const cost = ctx.state.nextCost(node, ctx.prestigeCostMul);
        const afford = ctx.resources.honey >= cost;
        var style = styleFor(lvl > 0, maxed, unlocked, afford);
        if (node.id == selectedId) {
            style.border = C.peach;
            style.borderThick = 3;
        }
        const selected = upgrade_tree.findNode(selectedId).?;
        for (selected.prereqs) |pr| {
            if (pr.id == node.id and !ctx.state.prereqMet(pr)) {
                style.border = C.peach;
            }
        }
        rl.drawRectangleRounded(rect, 0.12, 6, style.fill);
        rl.drawRectangleRoundedLinesEx(rect, 0.12, 6, style.borderThick * s, style.border);
        if (nodeFlash[node.id] > 0) rl.drawRectangleRounded(rect, 0.12, 6, withAlpha(C.green, @intFromFloat(70 * nodeFlash[node.id] / FLASH_TIME)));
        drawNodeIcon(ctx, node, pos.x + 23 * s, pos.y + 30 * s, 1.5 * s, unlocked);
        var nameBuf: [96]u8 = undefined;
        const name = std.fmt.bufPrintZ(&nameBuf, "{s}", .{locale.nodeName(node.id, node.name)}) catch "";
        // One name row and one cost/level row, with the icon spanning both.
        // Keep long translations intact; only their headings scale down.
        var nameSize = fs(20, s);
        const nameWidth = (NODE_W - 54) * s;
        while (nameSize > fs(14, s) and @as(f32, @floatFromInt(text.measure(name, nameSize))) > nameWidth) nameSize -= 1;
        text.draw(name, @intFromFloat(pos.x + 46 * s), @intFromFloat(pos.y + 8 * s), nameSize, style.nameColor);
        if (s >= 0.75) {
            var labelBuf: [40]u8 = undefined;
            const label = if (maxed) (if (node.isRepeatable()) locale.tr("Max", "Máx.") else locale.tr("Owned", "Obtido")) else if (!unlocked) locale.tr("Locked", "Bloqueado") else format.formatShort(cost, &labelBuf);
            text.draw(label, @intFromFloat(pos.x + 46 * s), @intFromFloat(pos.y + 35 * s), fs(18, s), style.costColor);
            if (node.repeat) |r| {
                var lb: [32]u8 = undefined;
                const level = std.fmt.bufPrintZ(&lb, "{s} {d}/{d}", .{ locale.tr("Lv", "Nv"), lvl, r.capAt(ctx.ascensions) }) catch "";
                text.draw(level, @as(i32, @intFromFloat(pos.x + (NODE_W - 10) * s)) - text.measure(level, fs(16, s)), @intFromFloat(pos.y + 36 * s), fs(16, s), C.subtext0);
            }
        }
        if (cheapest == node.id and !maxed and unlocked) {
            const label = locale.tr("Cheapest", "Mais barato");
            const size = fs(12, s);
            const tagW: f32 = @floatFromInt(text.measure(label, size));
            rl.drawRectangleRec(rl.Rectangle.init(pos.x + rect.width - tagW - 12, pos.y - 12 * s, tagW + 8, 18 * s), C.yellow);
            text.draw(label, @intFromFloat(pos.x + rect.width - tagW - 8), @intFromFloat(pos.y - 12 * s), size, C.base);
        }
    }
    ui_scale.endScissor();
    if (input.confirmReleased()) {
        dragging = false;
        pressedNode = null;
    }
    var action = drawDetails(ctx, details);
    const footerY = H - 52;
    if (widgets.button(rl.Rectangle.init(W - 138, footerY, 120, 38), locale.tr("Close", "Fechar"))) action = .close;
    if (widgets.buttonEx(rl.Rectangle.init(W - 248, footerY, 100, 38), locale.tr("Fit", "Ajustar"), .{ .face = C.surface2, .textColor = C.text })) fitView(content.width, content.height);
    if (widgets.buttonEx(rl.Rectangle.init(W - 358, footerY, 100, 38), "100%", .{ .face = C.surface2, .textColor = C.text })) {
        zoom = 1;
        focusNode(selectedId);
    }
    text.draw(if (input.gamepadActive()) locale.tr("Stick: pan · A: select", "Stick: mover · A: selecionar") else locale.tr("Drag: pan · click: select", "Arraste: mover · clique: selecionar"), 18, @intFromFloat(footerY + 12), 14, C.subtext0);
    return action;
}

// Shared wrapping for cards and the fixed inspector. Never shrink readable
// detail text to make room for a long translation.
fn wrapped(value: []const u8, x: f32, y: f32, width: f32, size: i32, color: rl.Color, maxLines: usize) f32 {
    var words = std.mem.tokenizeScalar(u8, value, ' ');
    var line: [384]u8 = undefined;
    var len: usize = 0;
    var row: usize = 0;
    const lineH: f32 = @floatFromInt(size + 5);
    while (words.next()) |word| {
        var candidate: [384]u8 = undefined;
        const joined = std.fmt.bufPrintZ(&candidate, "{s}{s}{s}", .{ line[0..len], if (len > 0) " " else "", word }) catch break;
        if (len > 0 and @as(f32, @floatFromInt(text.measure(joined, size))) > width) {
            line[len] = 0;
            text.draw(line[0..len :0], @intFromFloat(x), @intFromFloat(y + @as(f32, @floatFromInt(row)) * lineH), size, color);
            row += 1;
            if (row >= maxLines) return @as(f32, @floatFromInt(row)) * lineH;
            len = 0;
        }
        if (len > 0) {
            line[len] = ' ';
            len += 1;
        }
        if (len + word.len >= line.len) break;
        @memcpy(line[len..][0..word.len], word);
        len += word.len;
    }
    if (len > 0 and row < maxLines) {
        line[len] = 0;
        text.draw(line[0..len :0], @intFromFloat(x), @intFromFloat(y + @as(f32, @floatFromInt(row)) * lineH), size, color);
        row += 1;
    }
    return @as(f32, @floatFromInt(row)) * lineH;
}

fn drawDetails(ctx: TreeContext, rect: rl.Rectangle) TreeAction {
    const C = theme.CatppuccinMocha.Color;
    const node = upgrade_tree.findNode(selectedId) orelse &upgrade_tree.NODES[0];
    const lvl = ctx.state.level(node.id);
    const maxed = node.isMaxed(lvl, ctx.ascensions);
    const unlocked = ctx.state.isUnlocked(node);
    const cost = ctx.state.nextCost(node, ctx.prestigeCostMul);
    const wide = rect.width > 500;
    const x = rect.x + 16;
    const infoW = if (wide) rect.width * 0.56 - 24 else rect.width - 32;
    input.registerBlock(rect);
    rl.drawRectangleRounded(rect, 0.08, 6, C.base);
    var y = rect.y + 12;
    y += wrapped(locale.nodeName(node.id, node.name), x, y, infoW, 23, C.peach, 2);
    y += wrapped(locale.nodeDesc(node.id), x, y + 5, infoW, 17, C.text, if (wide) 3 else 5) + 10;
    var sb: [256]u8 = undefined;
    if (nodeStatus(ctx, node, lvl, &sb)) |status| _ = wrapped(status, x, y, infoW, 16, C.teal, 3);
    const ax = if (wide) rect.x + rect.width * 0.56 else x;
    const aw = if (wide) rect.width * 0.44 - 16 else infoW;
    var ay = if (wide) rect.y + 16 else rect.y + rect.height - 182;
    if (node.repeat) |r| {
        var lb: [64]u8 = undefined;
        const label = std.fmt.bufPrintZ(&lb, "{s} {d}/{d}", .{ locale.tr("Level", "Nível"), lvl, r.capAt(ctx.ascensions) }) catch "";
        text.draw(label, @intFromFloat(ax), @intFromFloat(ay), 20, C.teal);
        ay += 28;
    }
    var nb: [256]u8 = undefined;
    if (missingPrereqs(ctx, node, &nb)) |needs| {
        _ = wrapped(needs, ax, ay, aw, 16, C.peach, 4);
    } else if (ctx.resources.needsStorage(cost) and !maxed) {
        _ = wrapped(locale.tr("This price exceeds your storage capacity.", "Este preço excede seu armazém."), ax, ay, aw, 16, C.peach, 3);
    } else if (!maxed and ctx.resources.honey < cost) {
        if (ctx.resources.purchaseWait(cost)) |secs| {
            var eb: [16]u8 = undefined;
            if (format.formatEta(secs, &eb)) |eta| _ = wrapped(rl.textFormat(locale.tr("About %s at current production", "Cerca de %s na produção atual"), .{eta.ptr}), ax, ay, aw, 16, C.subtext1, 3);
        } else _ = wrapped(locale.tr("Waiting for honey production", "Aguardando produção de mel"), ax, ay, aw, 16, C.subtext1, 3);
    }
    const buttonRect = rl.Rectangle.init(ax, rect.y + rect.height - 50, aw, 38);
    if (ctx.resources.needsStorage(cost) and unlocked and !maxed) {
        if (widgets.button(buttonRect, locale.tr("Increase storage", "Aumentar armazém"))) focusNode(upgrade_tree.STORAGE_ID);
    } else {
        var cb: [32]u8 = undefined;
        const label = if (maxed) locale.tr("Owned / Max", "Obtido / Máx.") else if (!unlocked) locale.tr("Locked", "Bloqueado") else rl.textFormat(locale.tr("Buy · %s Honey", "Comprar · %s Mel"), .{format.formatShort(cost, &cb).ptr});
        if (widgets.buttonEx(buttonRect, label, .{ .enabled = unlocked and !maxed and ctx.resources.honey >= cost, .fontSize = 18 })) return .{ .purchase = node.id };
    }
    return .none;
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
