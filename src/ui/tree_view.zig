const rl = @import("raylib");
const text = @import("../text.zig");
const rg = @import("raygui");
const std = @import("std");

const theme = @import("../theme.zig");
const format = @import("../format.zig");
const upgrade_tree = @import("../upgrade_tree.zig");
const Resources = @import("../resources.zig").Resources;
const locale = @import("../localization.zig");

pub const TreeAction = union(enum) {
    none,
    close,
    purchase: upgrade_tree.NodeId,
};

const NODE_W: f32 = 158;
const NODE_H: f32 = 66;
const COL_SPACING: f32 = 174;
const ROW_SPACING: f32 = 74;

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

fn styleFor(purchased: bool, unlocked: bool, afford: bool) NodeStyle {
    const C = theme.CatppuccinMocha.Color;
    if (purchased) return .{
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
    if (afford) return .{
        .fill = C.surface0,
        .border = C.blue,
        .borderThick = 3,
        .nameColor = C.text,
        .costColor = C.yellow,
    };
    return .{
        .fill = C.surface0,
        .border = C.surface2,
        .borderThick = 2,
        .nameColor = C.subtext1,
        .costColor = C.red,
    };
}

fn nodePos(node: *const upgrade_tree.Node, centerX: f32, topY: f32) rl.Vector2 {
    const x = centerX + @as(f32, @floatFromInt(node.col)) * COL_SPACING - NODE_W / 2;
    const y = topY + @as(f32, @floatFromInt(node.row)) * ROW_SPACING;
    return rl.Vector2.init(x, y);
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

    const centerX = panelX + panelW / 2;
    const topY = panelY + 68;

    // Prereq lines first (behind nodes)
    for (&upgrade_tree.NODES) |*node| {
        const to = nodePos(node, centerX, topY);
        const toC = rl.Vector2.init(to.x + NODE_W / 2, to.y + NODE_H / 2);
        for (node.prereqs) |pid| {
            const pnode = upgrade_tree.findNode(pid) orelse continue;
            const from = nodePos(pnode, centerX, topY);
            const fromC = rl.Vector2.init(from.x + NODE_W / 2, from.y + NODE_H / 2);

            const thick: f32 = if (ctx.state.isPurchased(node.id)) 3 else 2;
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
    const mouse = rl.getMousePosition();

    for (&upgrade_tree.NODES) |*node| {
        const pos = nodePos(node, centerX, topY);
        const rect = rl.Rectangle.init(pos.x, pos.y, NODE_W, NODE_H);
        const purchased = ctx.state.isPurchased(node.id);
        const unlocked = ctx.state.isUnlocked(node);
        const afford = ctx.resources.honey >= node.cost;
        const style = styleFor(purchased, unlocked, afford);

        rl.drawRectangleRounded(rect, 0.22, 6, style.fill);
        rl.drawRectangleRoundedLinesEx(rect, 0.22, 6, style.borderThick, style.border);

        // Hover highlight on actionable nodes
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        if (!purchased and unlocked and afford and hovered) {
            var glow = C.blue;
            glow.a = 40;
            rl.drawRectangleRounded(rect, 0.22, 6, glow);
        }

        // Name
        var nameBuf: [64]u8 = undefined;
        const localizedName = locale.nodeName(node.id, node.name);
        const nameZ = std.fmt.bufPrintZ(&nameBuf, "{s}", .{localizedName}) catch continue;
        const nameW = text.measure(nameZ, 17);
        const nameX = @as(i32, @intFromFloat(pos.x + NODE_W / 2)) - @divFloor(nameW, 2);
        text.draw(nameZ, nameX, @as(i32, @intFromFloat(pos.y + 8)), 17, style.nameColor);

        // Cost / OWNED line
        if (style.showOwned) {
            const owned = locale.tr("OWNED", "ADQUIRIDO");
            const ow = text.measure(owned, 15);
            const ox = @as(i32, @intFromFloat(pos.x + NODE_W / 2)) - @divFloor(ow, 2);
            text.draw(owned, ox, @as(i32, @intFromFloat(pos.y + 39)), 15, style.costColor);
        } else if (!unlocked) {
            const locked = locale.tr("LOCKED", "BLOQUEADO");
            const lw = text.measure(locked, 15);
            const lx = @as(i32, @intFromFloat(pos.x + NODE_W / 2)) - @divFloor(lw, 2);
            text.draw(locked, lx, @as(i32, @intFromFloat(pos.y + 39)), 15, style.costColor);
        } else {
            var cbuf: [32]u8 = undefined;
            const cstr = format.formatShort(node.cost, &cbuf);
            const cw = text.measure(cstr, 16);
            const cx = @as(i32, @intFromFloat(pos.x + NODE_W / 2)) - @divFloor(cw, 2);
            text.draw(cstr, cx, @as(i32, @intFromFloat(pos.y + 38)), 16, style.costColor);
        }

        if (!purchased and unlocked and afford and hovered and rl.isMouseButtonPressed(rl.MouseButton.left)) {
            action = .{ .purchase = node.id };
        }
    }

    // Legend
    const legendY = panelY + panelH - 64;
    drawLegendChip(panelX + 18, legendY, locale.tr("Owned", "Adquirido"), C.green);
    drawLegendChip(panelX + 130, legendY, locale.tr("Ready", "Disponível"), C.blue);
    drawLegendChip(panelX + 270, legendY, locale.tr("Too pricy", "Muito caro"), C.red);
    drawLegendChip(panelX + 410, legendY, locale.tr("Locked", "Bloqueado"), C.overlay0);

    // Close button
    const closeW: f32 = 140;
    const closeH: f32 = 44;
    const closeX = panelX + panelW - closeW - 14;
    const closeY = panelY + panelH - closeH - 14;
    if (rg.button(rl.Rectangle.init(closeX, closeY, closeW, closeH), locale.tr("Close", "Fechar"))) {
        action = .close;
    }

    return action;
}

fn drawLegendChip(x: f32, y: f32, label: [:0]const u8, color: rl.Color) void {
    const chipSize: f32 = 12;
    rl.drawRectangleRounded(rl.Rectangle.init(x, y + 2, chipSize, chipSize), 0.4, 4, color);
    text.draw(label, @as(i32, @intFromFloat(x + chipSize + 6)), @as(i32, @intFromFloat(y - 2)), 17, theme.CatppuccinMocha.Color.subtext1);
}
