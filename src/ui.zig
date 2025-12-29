//! UI module - Re-exports all UI components
//!
//! This module provides a unified interface for all UI-related functionality:
//! - Hud: Main game HUD (honey, bees, beehive factor)
//! - pause_menu: Pause menu overlay
//! - popups: Tile interaction popups (beehive, flower, planting)

pub const hud = @import("ui/hud.zig");
pub const pause_menu = @import("ui/pause_menu.zig");
pub const popups = @import("ui/popups.zig");

// Re-export commonly used types for convenience
pub const Hud = hud.Hud;
pub const PauseMenuAction = pause_menu.PauseMenuAction;
pub const TilePopupAction = popups.TilePopupAction;
pub const TilePopupContext = popups.TilePopupContext;
