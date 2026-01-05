const rg = @import("raygui");
const rl = @import("raylib");

/// Catppuccin Mocha color palette
/// https://github.com/catppuccin/catppuccin
pub const CatppuccinMocha = struct {
    // Accent colors (u32 for raygui)
    pub const rosewater: u32 = 0xf5e0dcff;
    pub const flamingo: u32 = 0xf2cdcdff;
    pub const pink: u32 = 0xf5c2e7ff;
    pub const mauve: u32 = 0xcba6f7ff;
    pub const red: u32 = 0xf38ba8ff;
    pub const maroon: u32 = 0xeba0acff;
    pub const peach: u32 = 0xfab387ff;
    pub const yellow: u32 = 0xf9e2afff;
    pub const green: u32 = 0xa6e3a1ff;
    pub const teal: u32 = 0x94e2d5ff;
    pub const sky: u32 = 0x89dcebff;
    pub const sapphire: u32 = 0x74c7ecff;
    pub const blue: u32 = 0x89b4faff;
    pub const lavender: u32 = 0xb4befeff;

    // Text colors
    pub const text: u32 = 0xcdd6f4ff;
    pub const subtext1: u32 = 0xbac2deff;
    pub const subtext0: u32 = 0xa6adc8ff;

    // Overlay colors
    pub const overlay2: u32 = 0x9399b2ff;
    pub const overlay1: u32 = 0x7f849cff;
    pub const overlay0: u32 = 0x6c7086ff;

    // Surface colors
    pub const surface2: u32 = 0x585b70ff;
    pub const surface1: u32 = 0x45475aff;
    pub const surface0: u32 = 0x313244ff;

    // Base colors
    pub const base: u32 = 0x1e1e2eff;
    pub const mantle: u32 = 0x181825ff;
    pub const crust: u32 = 0x11111bff;

    /// rl.Color versions for rendering
    pub const Color = struct {
        pub const rosewater = rl.Color.init(0xf5, 0xe0, 0xdc, 0xff);
        pub const flamingo = rl.Color.init(0xf2, 0xcd, 0xcd, 0xff);
        pub const pink = rl.Color.init(0xf5, 0xc2, 0xe7, 0xff);
        pub const mauve = rl.Color.init(0xcb, 0xa6, 0xf7, 0xff);
        pub const red = rl.Color.init(0xf3, 0x8b, 0xa8, 0xff);
        pub const maroon = rl.Color.init(0xeb, 0xa0, 0xac, 0xff);
        pub const peach = rl.Color.init(0xfa, 0xb3, 0x87, 0xff);
        pub const yellow = rl.Color.init(0xf9, 0xe2, 0xaf, 0xff);
        pub const green = rl.Color.init(0xa6, 0xe3, 0xa1, 0xff);
        pub const teal = rl.Color.init(0x94, 0xe2, 0xd5, 0xff);
        pub const sky = rl.Color.init(0x89, 0xdc, 0xeb, 0xff);
        pub const sapphire = rl.Color.init(0x74, 0xc7, 0xec, 0xff);
        pub const blue = rl.Color.init(0x89, 0xb4, 0xfa, 0xff);
        pub const lavender = rl.Color.init(0xb4, 0xbe, 0xfe, 0xff);

        pub const text = rl.Color.init(0xcd, 0xd6, 0xf4, 0xff);
        pub const subtext1 = rl.Color.init(0xba, 0xc2, 0xde, 0xff);
        pub const subtext0 = rl.Color.init(0xa6, 0xad, 0xc8, 0xff);

        pub const overlay2 = rl.Color.init(0x93, 0x99, 0xb2, 0xff);
        pub const overlay1 = rl.Color.init(0x7f, 0x84, 0x9c, 0xff);
        pub const overlay0 = rl.Color.init(0x6c, 0x70, 0x86, 0xff);

        pub const surface2 = rl.Color.init(0x58, 0x5b, 0x70, 0xff);
        pub const surface1 = rl.Color.init(0x45, 0x47, 0x5a, 0xff);
        pub const surface0 = rl.Color.init(0x31, 0x32, 0x44, 0xff);

        pub const base = rl.Color.init(0x1e, 0x1e, 0x2e, 0xff);
        pub const mantle = rl.Color.init(0x18, 0x18, 0x25, 0xff);
        pub const crust = rl.Color.init(0x11, 0x11, 0x1b, 0xff);

        // Utility colors for overlays and effects
        pub const modalOverlay = rl.Color.init(0, 0, 0, 150);
        pub const pauseOverlay = rl.Color.init(0, 0, 0, 180);
        pub const pollenGlow = rl.Color.init(255, 255, 100, 128);
        pub const rebirthGlow = rl.Color.init(0xa6, 0xe3, 0xa1, 100); // green with low alpha
        pub const rebirthBubble = rl.Color.init(0xa6, 0xe3, 0xa1, 220); // green with high alpha
    };
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
