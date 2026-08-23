//! UI module - Re-exports all UI components
//!
//! This module provides a unified interface for all UI-related functionality:
//! - Hud: Main game HUD (honey, bees, beehive factor)
//! - pause_menu: Pause menu overlay
//! - title_screen: Title screen with play/quit buttons

pub const hud = @import("ui/hud.zig");
pub const pause_menu = @import("ui/pause_menu.zig");
pub const title_screen = @import("ui/title_screen.zig");
pub const side_panel = @import("ui/side_panel.zig");
pub const plant_menu = @import("ui/plant_menu.zig");
pub const options = @import("ui/options.zig");
pub const tree_view = @import("ui/tree_view.zig");

// Re-export commonly used types for convenience
pub const Hud = hud.Hud;
pub const PauseMenuAction = pause_menu.PauseMenuAction;
pub const TitleScreenAction = title_screen.TitleScreenAction;
pub const SidePanelContext = side_panel.SidePanelContext;
pub const TreeContext = tree_view.TreeContext;
pub const TreeAction = tree_view.TreeAction;
