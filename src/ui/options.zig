//! Options panel: window mode, language, volume, UI scale. Pure view — it
//! reports what the player changed and game.zig applies/persists it.

const rl = @import("raylib");
const text = @import("../text.zig");
const theme = @import("../theme.zig");
const locale = @import("../localization.zig");
const settings = @import("../settings.zig");
const input = @import("../input.zig");
const widgets = @import("widgets.zig");

pub const Action = union(enum) {
    none,
    back,
    window_mode: settings.WindowMode,
    language: locale.Language,
    music_volume: f32,
    fx_volume: f32,
    ui_scale: f32,
    cursor_snap: bool,
};

pub const Context = struct {
    screenWidth: f32,
    screenHeight: f32,
    windowMode: settings.WindowMode,
    language: locale.Language,
    musicVolume: f32,
    fxVolume: f32,
    uiScale: f32,
    cursorSnap: bool,
};

const PANEL_W: f32 = 520;
const PANEL_H: f32 = 540;
const ROW_H: f32 = 40;

/// Selected tab (session-sticky): 0 = General, 1 = Controls.
var tab: usize = 0;

pub fn draw(ctx: Context) Action {
    const C = theme.CatppuccinMocha.Color;
    rl.drawRectangle(0, 0, @intFromFloat(ctx.screenWidth), @intFromFloat(ctx.screenHeight), C.pauseOverlay);

    const px = (ctx.screenWidth - PANEL_W) / 2;
    const py = (ctx.screenHeight - PANEL_H) / 2;
    const panel = rl.Rectangle.init(px, py, PANEL_W, PANEL_H);
    rl.drawRectangleRounded(panel, 0.08, 10, C.surface0);
    rl.drawRectangleRoundedLinesEx(panel, 0.08, 10, 2, C.surface1);

    const title = locale.tr("Options", "Opções");
    text.draw(title, @as(i32, @intFromFloat(px + PANEL_W / 2)) - @divFloor(text.measure(title, 32), 2), @intFromFloat(py + 22), 32, C.text);

    const mouse = input.pointerPos();
    var action: Action = .none;

    // Tab strip
    {
        const names = [_][:0]const u8{ locale.tr("General", "Geral"), locale.tr("Controls", "Controles") };
        const tabsW: f32 = 300;
        if (drawSegments(px + (PANEL_W - tabsW) / 2, py + 70, tabsW, &names, tab, mouse)) |i| tab = i;
    }

    const startY = py + 132;
    switch (tab) {
        1 => drawControlsTab(ctx, px, startY, mouse, &action),
        else => drawGeneralTab(ctx, px, startY, mouse, &action),
    }

    // Back
    const bw: f32 = 200;
    const bh: f32 = 46;
    if (widgets.button(rl.Rectangle.init(px + (PANEL_W - bw) / 2, py + PANEL_H - bh - 22, bw, bh), locale.tr("Back", "Voltar"))) action = .back;

    return action;
}

fn drawGeneralTab(ctx: Context, px: f32, startY: f32, mouse: rl.Vector2, action: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const labelX = px + 28;
    const ctrlX = px + 200;
    const ctrlW = PANEL_W - 200 - 28;
    var y = startY;

    // Window mode
    drawLabel(locale.tr("Window", "Janela"), labelX, y);
    {
        const modes = [_]settings.WindowMode{ .windowed, .borderless, .fullscreen };
        const names = [_][:0]const u8{ locale.tr("Windowed", "Janela"), locale.tr("Borderless", "Sem bordas"), locale.tr("Fullscreen", "Tela cheia") };
        if (drawSegments(ctrlX, y, ctrlW, &names, @intFromEnum(ctx.windowMode), mouse)) |i| action.* = .{ .window_mode = modes[i] };
    }
    y += ROW_H + 16;

    // Language
    drawLabel(locale.tr("Language", "Idioma"), labelX, y);
    {
        const langs = [_]locale.Language{ .english, .portuguese_br };
        const names = [_][:0]const u8{ "English", "Português" };
        const sel: usize = if (ctx.language == .portuguese_br) 1 else 0;
        if (drawSegments(ctrlX, y, ctrlW, &names, sel, mouse)) |i| action.* = .{ .language = langs[i] };
    }
    y += ROW_H + 16;

    // Music volume
    drawLabel(locale.tr("Music", "Música"), labelX, y);
    {
        var v = ctx.musicVolume;
        const pct = rl.textFormat("%d%%", .{@as(i32, @intFromFloat(@round(v * 100)))});
        _ = widgets.slider(rl.Rectangle.init(ctrlX, y + 8, ctrlW - 64, ROW_H - 16), pct, &v, 0, 1);
        if (@abs(v - ctx.musicVolume) > 0.001) action.* = .{ .music_volume = v };
    }
    y += ROW_H + 16;

    // Sound-effects volume
    drawLabel(locale.tr("Effects", "Efeitos"), labelX, y);
    {
        var v = ctx.fxVolume;
        const pct = rl.textFormat("%d%%", .{@as(i32, @intFromFloat(@round(v * 100)))});
        _ = widgets.slider(rl.Rectangle.init(ctrlX, y + 8, ctrlW - 64, ROW_H - 16), pct, &v, 0, 1);
        if (@abs(v - ctx.fxVolume) > 0.001) action.* = .{ .fx_volume = v };
    }
    y += ROW_H + 16;

    // UI scale
    drawLabel(locale.tr("UI scale", "Escala da interface"), labelX, y);
    {
        var s = ctx.uiScale;
        const lbl = rl.textFormat("%.1fx", .{s});
        _ = widgets.slider(rl.Rectangle.init(ctrlX, y + 8, ctrlW - 64, ROW_H - 16), lbl, &s, 0.6, 2.5);
        if (@abs(s - ctx.uiScale) > 0.001) action.* = .{ .ui_scale = s };
    }
    y += ROW_H + 8;
    const hint = locale.tr("Alt+Enter: window/fullscreen   Cmd/Ctrl +/-: UI scale   N: mute", "Alt+Enter: janela/tela cheia   Cmd/Ctrl +/-: escala   N: mudo");
    text.draw(hint, @as(i32, @intFromFloat(px + PANEL_W / 2)) - @divFloor(text.measure(hint, 14), 2), @intFromFloat(y + 6), 14, C.overlay1);
}

fn drawControlsTab(ctx: Context, px: f32, startY: f32, mouse: rl.Vector2, action: *Action) void {
    const C = theme.CatppuccinMocha.Color;
    const labelX = px + 28;
    const ctrlX = px + 240;
    const ctrlW = PANEL_W - 240 - 28;
    var y = startY;

    // Tile snap for the gamepad cursor
    drawLabel(locale.tr("Tile snap (gamepad)", "Imã de célula (controle)"), labelX, y);
    {
        const names = [_][:0]const u8{ locale.tr("On", "Ligado"), locale.tr("Off", "Desligado") };
        const sel: usize = if (ctx.cursorSnap) 0 else 1;
        if (drawSegments(ctrlX, y, ctrlW, &names, sel, mouse)) |i| action.* = .{ .cursor_snap = i == 0 };
    }
    y += ROW_H + 20;

    // Bindings reference (display-only)
    const Binding = struct { name: [:0]const u8, keys: [:0]const u8 };
    const bindings = [_]Binding{
        .{ .name = locale.tr("Move cursor", "Mover cursor"), .keys = locale.tr("Mouse · Left stick", "Mouse · Analógico esq.") },
        .{ .name = locale.tr("Pan camera", "Mover câmera"), .keys = locale.tr("WASD/Arrows · Drag · Right stick", "WASD/Setas · Arrastar · Analógico dir.") },
        .{ .name = "Zoom", .keys = locale.tr("+/- · Wheel · Triggers", "+/- · Roda · Gatilhos") },
        .{ .name = locale.tr("Interact", "Interagir"), .keys = locale.tr("Click · A", "Clique · A") },
        .{ .name = locale.tr("Plant on tile", "Plantar na célula"), .keys = locale.tr("Click · A / X", "Clique · A / X") },
        .{ .name = locale.tr("Tech tree", "Árvore de melhorias"), .keys = "T · Y" },
        .{ .name = locale.tr("Quick-buy bees", "Compra rápida de abelhas"), .keys = locale.tr("1-4 · D-pad", "1-4 · Direcional") },
        .{ .name = locale.tr("Buy quantity", "Quantidade de compra"), .keys = "Tab · LB / RB" },
        .{ .name = locale.tr("Pause", "Pausa"), .keys = "Esc · Start" },
        .{ .name = locale.tr("Back / close", "Voltar / fechar"), .keys = "Esc · B" },
        .{ .name = locale.tr("Mute", "Mudo"), .keys = "N" },
    };
    for (bindings) |b| {
        text.draw(b.name, @intFromFloat(labelX), @intFromFloat(y), 16, C.subtext1);
        const kw = text.measure(b.keys, 16);
        text.draw(b.keys, @as(i32, @intFromFloat(px + PANEL_W - 28)) - kw, @intFromFloat(y), 16, C.text);
        y += 24;
    }
}

fn drawLabel(label: [:0]const u8, x: f32, y: f32) void {
    text.draw(label, @intFromFloat(x), @intFromFloat(y + 10), 19, theme.CatppuccinMocha.Color.subtext1);
}

/// Row of equal-width toggle buttons; returns the index clicked this frame.
fn drawSegments(x: f32, y: f32, w: f32, names: []const [:0]const u8, selected: usize, mouse: rl.Vector2) ?usize {
    const C = theme.CatppuccinMocha.Color;
    const n: f32 = @floatFromInt(names.len);
    const gap: f32 = 6;
    const segW = (w - gap * (n - 1)) / n;
    var clicked: ?usize = null;
    for (names, 0..) |name, i| {
        const sx = x + @as(f32, @floatFromInt(i)) * (segW + gap);
        const rect = rl.Rectangle.init(sx, y, segW, ROW_H);
        input.registerHotspot(rect);
        const hovered = rl.checkCollisionPointRec(mouse, rect);
        const isSel = i == selected;
        rl.drawRectangleRounded(rect, 0.3, 6, if (isSel) C.yellow else if (hovered) C.surface2 else C.surface1);
        const tw = text.measure(name, 17);
        text.draw(name, @as(i32, @intFromFloat(sx + segW / 2)) - @divFloor(tw, 2), @intFromFloat(y + 10), 17, if (isSel) C.base else C.text);
        if (hovered and input.confirmPressed()) clicked = i;
    }
    return clicked;
}
