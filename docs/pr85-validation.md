# PR #85 validation

This pass extends `072220c` (the existing UI polish PR) with flowers and the follow-up fixes requested in the conversation. Existing local Discoveries/planning/adjacency groundwork is preserved; planning controls remain disabled until the separate garden prototype integrates their lifecycle.

## Behavior checked

- `zig build check`, `zig build test`, `zig fmt --check src/ build.zig sprites/sprite_index.zig`.
- Headless ReleaseFast benchmark: 1 million bees / 41x41 / 1,200 ticks: approximately 0.48 ms/tick on this host. This covers simulation only, not rendering, and is not a before/after speedup claim.
- A 200-cycle flower create/destroy regression stays within two component slots and preserves a surviving flower's cached slot.
- Queue tests drain successive immutable save snapshots in order and round-trip all eight flower types. File replacement and sync remain atomic/durable through the existing save writer.
- Xvfb/llvmpipe playtest at 1280x800: select Storage, purchase it from the inspector, inspect a blocked colony upgrade without spending, open Discoveries, render the planter, load/save all eight species.
- English, Brazilian Portuguese, day/night, and increased UI scale captures. These are automated desktop interactions and visual inspections, not a physical Steam Deck/gamepad test.
- `BT_LANG` now takes precedence over the saved language for reproducible dev captures.

## Artwork

The original three strips are unchanged. The five additional 160x32 strips use the source's five living frames, reversed and enlarged 2x without interpolation. The script checks exact alpha preservation and membership in the Mocha palette. Dark source shades map to dark Mocha shades so flowers remain distinguishable on the grass during daylight.

Catppify (Mocha noise 0/4) and Catppuccin Factory (stock/current Mocha; ImageGoNord 1.2.0) comparisons are attached to the PR. The imagegen concept was rejected and is not shipped.

## Limits

- New flower niche values are an initial balance pass; extended economy playtesting is still needed.
- Large-meadow GPU performance needs hardware profiling. This pass fixes unbounded component growth and takes autosave disk I/O off the frame path; it does not claim a rendering FPS improvement.
- The supplied Steam marketing/upload files and unrelated worktrees are outside this PR.
