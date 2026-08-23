//! Compact "plant a flower" chooser that opens when the player clicks an
//! empty meadow tile. Three rows (one per flower type) with sprite, name and
//! cost; clicking outside or pressing Esc closes it.

const rl = @import("raylib");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
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
};

pub const State = struct {
    open: bool = false,
    tileX: i32 = 0,
    tileY: i32 = 0,

    pub fn openAt(self: *@This(), x: i32, y: i32) void {
        self.open = true;
        self.tileX = x;
        self.tileY = y;
    }
};

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    resources: *const Resources,
    textures: *const Textures,
};

const ROW_H: f32 = 44;
const PANEL_W: f32 = 190;
const PAD: f32 = 8;

const Entry = struct { flower: Flowers, cost: f32 };
const ENTRIES = [_]Entry{
    .{ .flower = .dandelion, .cost = spawners.FLOWER_COSTS.dandelion },
    .{ .flower = .rose, .cost = spawners.FLOWER_COSTS.rose },
    .{ .flower = .tulip, .cost = spawners.FLOWER_COSTS.tulip },
};

fn flowerName(f: Flowers) [:0]const u8 {
    return switch (f) {
        .rose => locale.tr("Rose", "Rosa"),
        .tulip => locale.tr("Tulip", "Tulipa"),
        .dandelion => locale.tr("Dandelion", "Dente-de-leão"),
    };
}

/// Draw the menu anchored under its tile and return what the player did.
pub fn draw(state: *const State, ctx: Context) Action {
    const C = theme.CatppuccinMocha.Color;
    const panelH: f32 = PAD * 2 + 24 + ROW_H * ENTRIES.len;

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

    const mouse = rl.getMousePosition();
    const clicked = rl.isMouseButtonPressed(rl.MouseButton.left);
    var action: Action = .none;

    for (ENTRIES, 0..) |entry, i| {
        const ry = py + PAD + 24 + ROW_H * @as(f32, @floatFromInt(i));
        const row = rl.Rectangle.init(px + PAD, ry, PANEL_W - PAD * 2, ROW_H - 4);
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

        text.draw(flowerName(entry.flower), @intFromFloat(row.x + 44), @intFromFloat(row.y + 11), 17, if (afford) C.text else C.overlay0);

        var cbuf: [32]u8 = undefined;
        const cstr = format.formatShort(entry.cost, &cbuf);
        const costLabel = rl.textFormat("%s", .{cstr.ptr});
        const cw: f32 = @floatFromInt(text.measure(costLabel, 15));
        const dropR: f32 = 4.5;
        const cx = row.x + row.width - cw - 10;
        icons.drawHoneyDrop(cx - dropR - 5, row.y + row.height / 2 + dropR * 0.65, dropR, if (afford) C.yellow else C.overlay0);
        text.draw(costLabel, @intFromFloat(cx), @intFromFloat(row.y + 12), 15, if (afford) C.yellow else C.overlay0);

        if (clicked and hovered and afford) action = .{ .plant = entry.flower };
    }

    // Click anywhere outside the panel closes it.
    if (clicked and action == .none and !rl.checkCollisionPointRec(mouse, panel)) action = .close;
    return action;
}
