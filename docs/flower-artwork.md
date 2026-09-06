# Flower artwork and Mocha conversion

The purchased source is **8flowers by Brysiaa**, a 96x128 transparent sheet containing eight rows and six stages per row. Keep the purchased original external; all eight flowers now use the same Mocha remap. The earlier hand-redrawn Rose, Tulip and Dandelion are preserved in git history and PR comparisons.

## Reproduce the new sprites

Install Pillow in a development environment, then run:

```sh
python tools/remap_flowers.py '/path/to/8flowers by Brysiaa.png'
```

The script reads the current Mocha constants from `src/theme.zig`, maps foliage and petal color families separately, preserves every alpha value, reverses the five living stages into seed-to-mature order, and enlarges by exactly 2x using nearest-neighbor sampling. It writes 160x32 strips for Rose, Tulip, Dandelion, Pink Tulip, Poppy, Hyacinth, Red Tulip, and Iris. This deliberately replaces the first three hand redraws with source-shape remaps at the user’s request; names, enum IDs, growth timing and balance are unchanged. Display names describe their in-game roles/appearance, not botanical identifications supplied by the artist. Withered sprites are baked from these strips by the same grayscale loader as existing flowers.

Color maps and enlarged comparisons go to `output/flower-comparison/`. The script verifies exact transparency preservation and that all visible remapped colors belong to Mocha. This is a palette adaptation; it does not add new outlines or redraw silhouettes.

## Alternatives compared

- [Catppify](https://github.com/raluvy95/catppify): ran Mocha with noise 0 and 4. Alpha preserved.
- [Catppuccin Factory](https://github.com/Fxzzi/catppuccin-factory): ran its stock palette and the current [Mocha palette](https://catppuccin.com/palette/), through ImageGoNord 1.2.0. Alpha preserved. The stock palette predates current Mocha.
- Flower-aware remap: only current Mocha colors; light green/teal foliage matches the existing game's bright foliage more closely.

Direct converters map many saturated dark greens to gray or near-background colors. The flower-aware version retains readability against a dark meadow. The comparison images and the three previous game references are attached to PR #85 on the `pr-assets` branch.

An initial imagegen experiment was rejected because it changed shapes and frame alignment. None of its pixels are used by the game.
