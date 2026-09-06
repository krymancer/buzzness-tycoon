# Garden planner — disposable native prototype

**Question:** Does choosing a flower layout make tending the meadow interesting without making the idle game feel like work?

Based on PR #85. This branch activates the existing planning and adjacency groundwork. Run `just poc-garden` (or `bash tools/prototype/garden.sh`). It creates a temporary meadow with 1,500 honey, workers and gardeners; Steam integration is disabled. The temporary directory is removed when you exit. The production save is not read. Plans are session-only, even in the temporary save.

## Try it

1. Click an empty tile and choose any of the eight flowers. Drag across neighboring tiles: the plan is free, and empty cells are planted while honey allows.
2. Paint three connected flowers of the same type. Hover them to see the cluster highlight and +50% pollen bonus.
3. Try three different flower types in one orthogonal neighborhood (×2). Rose next to the original Tulip adds +25%; distance from the hive adds 4% per ring. These values are experiments, not a balanced economy proposal.
4. Press **P** over a tile to change brush, or use gamepad X. Choose **Clear plan** to erase blueprints without destroying living flowers. Esc/B or right-click drops the brush. After dropping the brush, mouse dragging pans again.
5. Spend your honey, then paint another plan: ghosts remain and wild growth/gardeners use the planned species. Occupied tiles keep their current flower until it dies. Grid expansion shifts the plan with the meadow; a new run clears it.

The bottom strip exposes the active brush and plan count. Hover labels show actual/preview multipliers. The normal executable behavior remains gated behind `BT_POC_GARDEN`; the launcher also supplies a disposable save explicitly. Prototype runs skip Steam initialization even if the library is present.

## Playtest and limits

`zig build check`, `zig build test`, ReleaseFast build, and formatting pass. Xvfb desktop interaction checks three connected painted cells, their purchased flowers in the resulting save, and free planning with zero honey. Brush cancellation and erasing are visually inspected in the PR captures. This is a short automated desktop playtest, not a physical controller session or economy balance test.

No production persistence/migrations for plans. Very fast mouse motion can skip cells between frames. Larger bonuses may overwhelm flower niches. Adjacency rebuilds when flowers change, so a large-meadow stress test is required before promotion. Withering now invalidates the bonus cache as well as the draw cache.

## Decision to review

Keep the brush/ghost interaction if it makes arranging flowers enjoyable. Judge the bonus rules separately: perhaps only the same-species cluster deserves to ship first. A useful follow-up is a five-minute human playtest: can a new player form a cluster, understand its bonus, change the plan, and return to idle play without instructions?
