# UI system

The current UI lives in `src/ui/`, drawn with Raylib and the shared BoldPixels font. Pixel buttons use `widgets.zig`; Mocha colors are defined in `theme.zig`. `ui_scale.zig` maps framebuffer pixels and input into the same logical canvas.

## Meadow HUD

`hud.zig` uses a 48-logical-pixel strip: honey/capacity, income or a full-storage warning, and a thin meter. Hover (including the controller cursor) reveals overflowing production and hive/night multipliers. Selecting the strip focuses Storage in the existing tree. The translucent backing permits single-pass text instead of nine outline passes.

`action_hud.zig` owns the bee purchase cross, bulk quantity, census, Instant Grow/Aura status, Prestige, Discoveries, and tree button. Focusing a bee slot shows its name, role, quantity, total price, ownership, and milestone. Purchases above current capacity point to Storage instead of displaying an impossible ETA. The tree badge counts affordable upgrades and shows the exact affordable count in a fixed, high-contrast pixel badge.

## Upgrade tree

`tree_view.zig` is a full-screen pannable map. It opens at a readable scale, remembers selection/pan/zoom across visits, and provides Bees/Honey/Meadow/Colony/Labs shortcuts. Fit is an optional overview. Node selection and purchase are separate actions; dragging cannot purchase. Visible locked nodes remain controller-focusable.

The selected upgrade has a fixed inspector on wide logical canvases, or below the map on narrower ones. Its description, Now/Next effect, level/cap, missing prerequisites, and buy action stay readable independently of map zoom. ETAs live here rather than competing with card levels. "Cheapest" is a price hint, not a claim about the best strategy.

The simulation continues while full-screen views are open; the covered meadow is not rendered.

## Planting and achievements

`plant_menu.zig` lists all eight flowers with price and niche. `discoveries_view.zig` is a scrollable achievement book sharing the Steam/local tracker. New flower IDs are appended after the original three, and the original Botanical Trifecta still refers to Rose, Tulip, and Dandelion.

## Verification

Use throwaway `BT_SAVE_PATH` files. Check English and Portuguese at 1280x800, 1920x1080, and increased UI scale; inspect unaffordable, storage-blocked, locked, purchased, and capped nodes. `zig build check`, `zig build test`, and the headless `zig build bench -Doptimize=ReleaseFast` cover compile, behavior, and simulation checks. Rendering captures require a display or Xvfb.

BoldPixels is loaded unchanged with point filtering and no extra letter spacing. The badge uses a 16px label; other UI sizes still follow the existing scale setting, so arbitrary window/UI scales are not guaranteed to be pixel-integer multiples. Attribution and the font notice ship with Steam staging and release archives.
