const rl = @import("raylib");
const text = @import("../text.zig");
const std = @import("std");
const input = @import("../input.zig");
const widgets = @import("widgets.zig");

const theme = @import("../theme.zig");
const format = @import("../format.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");
const ui_scale = @import("../ui_scale.zig");

pub const TreeAction = union(enum) {
    none,
    close,
    purchase: upgrade_tree.NodeId,
};

const NODE_W: f32 = 158;
const NODE_H: f32 = 66;
const COL_SPACING: f32 = 174;
const ROW_SPACING: f32 = 74;
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
        if (buyable) input.registerHotspot(rect);
        if (buyable and afford and hovered) {
            var glow = C.blue;
            glow.a = 40;
            rl.drawRectangleRounded(rect, 0.22, 6, glow);
        }

        // Name
        var nameBuf: [64]u8 = undefined;
        const localizedName = locale.nodeName(node.id, node.name);
        const nameZ = if (node.isRepeatable() and lvl > 0)
            std.fmt.bufPrintZ(&nameBuf, "{s} {s}{d}", .{ localizedName, locale.tr("Lv", "Nv"), lvl }) catch continue
        else
            std.fmt.bufPrintZ(&nameBuf, "{s}", .{localizedName}) catch continue;
        const nameSize = fs(17, s);
        const nameW = text.measure(nameZ, nameSize);
        const nameX = @as(i32, @intFromFloat(pos.x + nodeW / 2)) - @divFloor(nameW, 2);
        text.draw(nameZ, nameX, @as(i32, @intFromFloat(pos.y + 8 * s)), nameSize, style.nameColor);

        // Cost line — only on nodes that can still be bought; owned and
        // locked states already read through the border/text colors.
        if (!style.showOwned and unlocked) {
            const subY: i32 = @intFromFloat(pos.y + 39 * s);
            var cbuf: [32]u8 = undefined;
            const cstr = format.formatShort(cost, &cbuf);
            const costSize = fs(16, s);
            const cw = text.measure(cstr, costSize);
            text.draw(cstr, @as(i32, @intFromFloat(pos.x + nodeW / 2)) - @divFloor(cw, 2), subY, costSize, style.costColor);
        }

        if (buyable and afford and hovered and clickOk and input.confirmReleased()) {
            action = .{ .purchase = node.id };
        }
    }

    ui_scale.endScissor();

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

