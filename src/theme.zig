const rg = @import("raygui");

pub const CatppuccinMocha = struct {
    pub const yellow: u32 = 0xf9e2afff;
    pub const peach: u32 = 0xfab387ff;
    pub const text: u32 = 0xcdd6f4ff;
    pub const subtext0: u32 = 0xa6adc8ff;
    pub const surface2: u32 = 0x585b70ff;
    pub const surface1: u32 = 0x45475aff;
    pub const surface0: u32 = 0x313244ff;
    pub const base: u32 = 0x1e1e2eff;
};

pub fn applyCatppuccinMochaTheme() void {
    rg.loadStyleDefault();

    rg.setStyle(rg.Control.default, .{ .default = rg.DefaultProperty.background_color }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.base))));
    rg.setStyle(rg.Control.default, .{ .default = rg.DefaultProperty.text_size }, 16);
    rg.setStyle(rg.Control.default, .{ .default = rg.DefaultProperty.text_spacing }, 1);

    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.base_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.yellow))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.base_color_focused }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.peach))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.base_color_pressed }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.peach))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.base_color_disabled }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface0))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.text_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.base))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.text_color_focused }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.base))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.text_color_pressed }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.base))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.text_color_disabled }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.subtext0))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.border_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface1))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.border_color_focused }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface2))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.border_color_pressed }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface2))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.border_color_disabled }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface0))));
    rg.setStyle(rg.Control.button, .{ .control = rg.ControlProperty.border_width }, 1);

    rg.setStyle(rg.Control.label, .{ .control = rg.ControlProperty.text_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.text))));
    rg.setStyle(rg.Control.label, .{ .control = rg.ControlProperty.text_color_focused }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.text))));
    rg.setStyle(rg.Control.label, .{ .control = rg.ControlProperty.text_color_pressed }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.text))));

    rg.setStyle(rg.Control.default, .{ .control = rg.ControlProperty.base_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface0))));
    rg.setStyle(rg.Control.default, .{ .control = rg.ControlProperty.border_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.surface1))));
    rg.setStyle(rg.Control.default, .{ .control = rg.ControlProperty.text_color_normal }, @bitCast(@as(i32, @bitCast(CatppuccinMocha.text))));
}
