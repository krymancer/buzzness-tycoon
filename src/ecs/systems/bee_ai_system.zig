const std = @import("std");
const rl = @import("raylib");
const World = @import("../world.zig").World;
const Entity = @import("../entity.zig").Entity;
const components = @import("../components.zig");
const textures = @import("../../textures.zig");
const Textures = textures.Textures;
const Flowers = textures.Flowers;
const utils = @import("../../utils.zig");
const Resources = @import("../../resources.zig").Resources;
const labs_mod = @import("../../labs.zig");
const lifespan_system = @import("lifespan_system.zig");
const prestige_mod = @import("../../prestige.zig");
const spawners = @import("../../spawners.zig");
const grid_mod = @import("../../grid.zig");
const config = @import("../../config.zig");

var pollinationTimer: f32 = 0;
const POLLINATION_CHECK_INTERVAL: f32 = 0.5;
const SEARCH_COOLDOWN: f32 = 0.3;
const MOVEMENT_LEAP_FACTOR: f32 = 2.0;

// Bees take their full decision step every STAGGER_GROUPS frames (with a
// matching delta), and only interpolate toward their target in between.
const STAGGER_GROUPS: usize = 4;
var currentStaggerGroup: usize = 0;

var cachedBeehiveEntity: ?Entity = null;
var cachedBeehiveGridX: f32 = 0;
var cachedBeehiveGridY: f32 = 0;
var beehiveCacheInitialized: bool = false;

// Camera/meadow state for this frame, shared by the per-bee helpers so the
// hot loop passes no extra arguments around.
var frameGridOffset: rl.Vector2 = .{ .x = 0, .y = 0 };
var frameGridScale: f32 = 1;
var frameGridWidth: usize = 0;
var frameGridHeight: usize = 0;
var frameBeehivePos: rl.Vector2 = .{ .x = 0, .y = 0 };
var framePlantChance: i32 = GARDENER_BASE_CHANCE;

/// The flower cache is sized for the largest meadow, so no bee is ever
/// left without a target because the cache filled up.
const MAX_CELLS: usize = grid_mod.MAX_WIDTH * grid_mod.MAX_WIDTH;
const MAX_AVAILABLE_FLOWERS: usize = MAX_CELLS;
const MAX_BEES_PER_FLOWER: u32 = 3;
var availableFlowers: [MAX_AVAILABLE_FLOWERS]AvailableFlower = undefined;
// Screen-space positions for the cache entries, recomputed once per frame
// (the camera can move between frames) so per-bee searches touch no
// transforms and no HashMaps — at large populations tens of thousands of
// bees can search in the same frame.
var availableFlowerWorldPos: [MAX_AVAILABLE_FLOWERS]rl.Vector2 = undefined;
var availableFlowerCount: usize = 0;

// Spatial index over the cache: grid cell -> cache entry. A searching bee
// scans the square of cells around its own tile instead of the whole
// cache, so search cost no longer grows with the meadow. Kept in step with
// the cache's swap-removes.
const NO_ENTRY: u16 = std.math.maxInt(u16);
var cellEntry: [MAX_CELLS]u16 = undefined;
var cellStride: usize = 0;
var cellRows: usize = 0;
/// Half-side of the local scan square, in tiles.
const LOCAL_SEARCH_RADIUS: i32 = 6;
/// Bees with no flower nearby sample this many cache entries from a random
/// offset, so a search is O(1) whatever the meadow size.
const FALLBACK_SCAN: usize = 256;

const AvailableFlower = struct {
    entity: Entity,
    gridX: f32,
    gridY: f32,
    /// Free target slots left, snapshotted at cache build and decremented as
    /// bees claim them; entries drop out of the scan at zero.
    slots: u32,
    /// Index into cellEntry (anchor cell); unused for the rotten list.
    cell: u32,
};

// Rotten flowers gardeners should fly to and clear (Composting node).
// One claimant per flower — clearing is instant on arrival, so extra
// sweepers would waste trips.
const MAX_ROTTEN_FLOWERS: usize = 1024;
var rottenFlowers: [MAX_ROTTEN_FLOWERS]AvailableFlower = undefined;
var rottenFlowerWorldPos: [MAX_ROTTEN_FLOWERS]rl.Vector2 = undefined;
var rottenFlowerCount: usize = 0;

// Seed Scouts: tile occupancy for the empty-cell search, rebuilt with the
// flower cache. Claims stop every idle gardener converging on one gap and
// are re-derived from the bees' live sow targets on each rebuild, so a bee
// retired mid-trip can't pin a cell forever.
var cellOccupied: [MAX_CELLS]bool = undefined;
var cellSowClaimed: [MAX_CELLS]bool = undefined;
/// Random tiles probed when no gap is within the local scan square.
const SOW_FALLBACK_PROBES: usize = 64;

/// Untargeted bees wander, but never further than this many tiles past the
/// meadow's edge: beyond it they turn back toward the hive, so an idle
/// swarm hovers over the field instead of tiling the whole window.
pub const WANDER_MARGIN_TILES: f32 = 2.0;

pub const UpdateCtx = struct {
    world: *World,
    deltaTime: f32,
    gridOffset: rl.Vector2,
    gridScale: f32,
    gridWidth: usize,
    gridHeight: usize,
    texturesRef: Textures,
    resources: *Resources,
    labs: *const labs_mod.LabState,
    prestige: *prestige_mod.PrestigeState,
    honeyFactor: f32,
    /// Sky night factor for this frame: 0 = full day, 1 = deep night.
    nightFactor: f32,
    frameHoneyGain: *f32,
};

pub fn resetCaches() void {
    cachedBeehiveEntity = null;
    beehiveCacheInitialized = false;
    availableFlowerCount = 0;
    rottenFlowerCount = 0;
    cellStride = 0;
    cellRows = 0;
    currentStaggerGroup = 0;
    pollinationTimer = 0;
}

pub fn update(ctx: UpdateCtx) !void {
    const store = &ctx.world.bees;
    store.meadow = .{
        .offset = ctx.gridOffset,
        .scale = ctx.gridScale,
        .width = ctx.gridWidth,
        .height = ctx.gridHeight,
    };
    // Purchases past the simulation cap and deaths change the colony's mix;
    // fold them into the simulated swarm before it moves.
    if (store.needsRebalance) try ctx.world.rebalanceBees();
    if (!config.bees_immortal) store.age(ctx.world, ctx.deltaTime);

    frameGridOffset = ctx.gridOffset;
    frameGridScale = ctx.gridScale;
    frameGridWidth = ctx.gridWidth;
    frameGridHeight = ctx.gridHeight;

    const scaledDeltaTime = ctx.deltaTime * @as(f32, @floatFromInt(STAGGER_GROUPS));

    // Night penalty: honey and speed ramp down smoothly with the night
    // factor, scaled back by the Night Shift node (see nightPenaltyScale).
    const nightHoney = nightHoneyMul(ctx.nightFactor);
    // Tailwind rides along with the night speed factor: every flight below
    // multiplies the type's own speed by this one number.
    const nightSpeed = nightSpeedMul(ctx.nightFactor) * beeSpeedMul;

    pollinationTimer += ctx.deltaTime;
    const checkPollination = pollinationTimer >= POLLINATION_CHECK_INTERVAL;
    if (checkPollination) pollinationTimer = 0;

    if (!beehiveCacheInitialized) {
        cachedBeehiveEntity = findBeehive(ctx.world);
        if (cachedBeehiveEntity) |e| {
            if (ctx.world.getGridPosition(e)) |gp| {
                cachedBeehiveGridX = gp.x;
                cachedBeehiveGridY = gp.y;
            }
        }
        beehiveCacheInitialized = true;
    }

    if (currentStaggerGroup == 0) {
        buildAvailableFlowersCache(ctx.world, ctx.gridWidth, ctx.gridHeight);
        if (gardenerSow) buildOccupancy(ctx.world);
    }
    for (0..availableFlowerCount) |i| {
        availableFlowerWorldPos[i] = getWorldPosFromGrid(availableFlowers[i].gridX, availableFlowers[i].gridY, ctx.gridOffset, ctx.gridScale);
    }
    for (0..rottenFlowerCount) |i| {
        rottenFlowerWorldPos[i] = getWorldPosFromGrid(rottenFlowers[i].gridX, rottenFlowers[i].gridY, ctx.gridOffset, ctx.gridScale);
    }

    const beehiveWorldPos = getWorldPosFromGrid(cachedBeehiveGridX, cachedBeehiveGridY, ctx.gridOffset, ctx.gridScale);
    frameBeehivePos = beehiveWorldPos;

    // Each simulated gardener stands for `weight` colony gardeners; its
    // planting roll is the chance that any of them would have planted.
    framePlantChance = effectivePlantChance(gardenerPlantChance, store.weight(.gardener));

    const slice = store.list.slice();
    const positions = slice.items(.pos);
    const ais = slice.items(.ai);
    const collectors = slice.items(.collector);

    for (0..slice.len) |beeIndex| {
        const isInStaggerGroup = beeIndex % STAGGER_GROUPS == currentStaggerGroup;
        const beeAI = &ais[beeIndex];
        const position = &positions[beeIndex];

        // Off-frame bees: interpolate toward cached target for smooth visuals.
        if (!isInStaggerGroup) {
            if (beeAI.targetLocked) {
                const targetPos = if (beeAI.carryingPollen)
                    beehiveWorldPos
                else
                    getWorldPosFromGrid(beeAI.targetGridX, beeAI.targetGridY, ctx.gridOffset, ctx.gridScale);
                moveTowards(position, targetPos, ctx.deltaTime);
            } else if (beeAI.scatterTimer > 0) {
                beeAI.scatterTimer -= ctx.deltaTime;
                performRandomWalk(beeAI, position, ctx.deltaTime);
            }
            continue;
        }

        if (beeAI.searchCooldown > 0) beeAI.searchCooldown -= scaledDeltaTime;

        if (beeAI.scatterTimer > 0) {
            beeAI.scatterTimer -= scaledDeltaTime;
            performRandomWalk(beeAI, position, scaledDeltaTime);
            continue;
        }

        // Composting runs on every cell a gardener crosses, whatever it is
        // doing — rot must be clearable even when there's no pollen around.
        if (gardenerCompost and beeAI.beeType.canSpawnFlowers()) {
            try handleComposting(ctx.world, beeAI, position, ctx.gridOffset, ctx.gridScale, ctx.gridWidth, ctx.gridHeight);
        }

        if (checkPollination and beeAI.carryingPollen) {
            try handlePollination(ctx.world, beeAI, position, ctx.gridOffset, ctx.gridScale, ctx.gridWidth, ctx.gridHeight, ctx.texturesRef);
        }

        if (beeAI.carryingPollen) {
            if (!beeAI.targetLocked) {
                beeAI.targetEntity = cachedBeehiveEntity;
                if (beeAI.targetEntity != null) {
                    beeAI.targetLocked = true;
                    beeAI.targetGridX = cachedBeehiveGridX;
                    beeAI.targetGridY = cachedBeehiveGridY;
                }
            }

            const distance = rl.math.vector2Distance(position.toVector2(), beehiveWorldPos);
            if (distance < 30.0) {
                const collector = &collectors[beeIndex];
                if (collector.pollenCollected > 0) {
                    const newHoney = collector.pollenCollected * ctx.honeyFactor * ctx.prestige.globalMul() * nightHoney;
                    ctx.resources.addHoney(newHoney);
                    ctx.prestige.trackHoney(newHoney);
                    ctx.frameHoneyGain.* += newHoney;
                    collector.pollenCollected = 0;

                    beeAI.carryingPollen = false;
                    beeAI.tripLoads = 0;
                    beeAI.targetLocked = false;
                    beeAI.targetEntity = null;
                }
            } else {
                moveTowardsWithSpeed(position, beehiveWorldPos, scaledDeltaTime, beeAI.beeType.getSpeedMultiplier() * nightSpeed);
            }
            continue;
        }

        if (!beeAI.targetLocked) {
            if (beeAI.searchCooldown <= 0) {
                // Composting: gardeners hunt rot first — clearing dead
                // flowers is their job once the node is owned.
                var found: ?FlowerHit = null;
                if (beeAI.beeType.canSpawnFlowers()) {
                    if (gardenerSweep) {
                        found = findNearestFromCache(position.toVector2(), &rottenFlowers, &rottenFlowerWorldPos, &rottenFlowerCount);
                    }
                    // Seed Scouts: gaps come before pollen — gardeners are
                    // groundskeepers first, foragers second.
                    if (found == null and gardenerSow) {
                        if (findEmptyCell(position.toVector2())) |cell| {
                            beeAI.targetEntity = null;
                            beeAI.targetGridX = cell.x;
                            beeAI.targetGridY = cell.y;
                            beeAI.targetLocked = true;
                            beeAI.sowTarget = true;
                        }
                    }
                }
                if (found == null and !beeAI.targetLocked) found = findNearestFlowerFromCache(position.toVector2());
                if (found) |hit| {
                    beeAI.targetEntity = hit.entity;
                    beeAI.targetGridX = hit.gridX;
                    beeAI.targetGridY = hit.gridY;
                    beeAI.targetLocked = true;
                    ctx.world.incrementFlowerTarget(hit.entity);
                } else {
                    beeAI.searchCooldown = SEARCH_COOLDOWN;
                    // Saddlebags: nothing left to top the bag up with, so
                    // deliver what's in it rather than wander with it.
                    if (collectors[beeIndex].pollenCollected > 0) beeAI.carryingPollen = true;
                }
            }

            if (!beeAI.targetLocked) {
                performRandomWalk(beeAI, position, scaledDeltaTime);
            }
            continue;
        }

        if (beeAI.sowTarget) {
            try handleSowTrip(ctx, beeAI, position, scaledDeltaTime, nightSpeed);
            continue;
        }

        const targetEntity = beeAI.targetEntity orelse {
            performRandomWalk(beeAI, position, scaledDeltaTime);
            continue;
        };

        const targetFlower = ctx.world.getFlowerGrowth(targetEntity);
        if (targetFlower == null) {
            ctx.world.decrementFlowerTarget(targetEntity);
            beeAI.targetLocked = false;
            beeAI.targetEntity = null;
            continue;
        }

        const targetPos = getWorldPosFromGrid(beeAI.targetGridX, beeAI.targetGridY, ctx.gridOffset, ctx.gridScale);
        const distance = rl.math.vector2Distance(position.toVector2(), targetPos);

        if (distance < 5.0) {
            if (targetFlower.?.isRotten) {
                // Composting: clear the rot on arrival so the cell can
                // regrow (removeFlower also drops the target count).
                try lifespan_system.removeFlower(ctx.world, targetEntity);
                rottenClearedPending += 1;
                beeAI.targetLocked = false;
                beeAI.targetEntity = null;
                beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(4, 10))) / 10.0;
                continue;
            }
            if (targetFlower.?.state == 4 and targetFlower.?.hasPollen) {
                targetFlower.?.hasPollen = false;
                // Saddlebags: keep foraging until the bag is full, then
                // head home with the whole load in one trip.
                beeAI.tripLoads +|= 1;
                beeAI.carryingPollen = beeAI.tripLoads >= bagCapacity;

                const collectionMultiplier = beeAI.beeType.getCollectionMultiplier();
                // Lab: Aura boosts flowers inside its rings around the hive.
                const auraMul = ctx.labs.pollenMultiplierAt(beeAI.targetGridX, beeAI.targetGridY, cachedBeehiveGridX, cachedBeehiveGridY);
                collectors[beeIndex].collect(1.0 * targetFlower.?.pollenMultiplier * collectionMultiplier * auraMul);

                // Short dawdle after collecting, then head to the hive — long
                // scatter here was the main throttle on honey throughput.
                beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(6, 14))) / 10.0;
            }

            ctx.world.decrementFlowerTarget(targetEntity);
            beeAI.targetLocked = false;
            beeAI.targetEntity = null;
        } else {
            moveTowardsWithSpeed(position, targetPos, scaledDeltaTime, beeAI.beeType.getSpeedMultiplier() * nightSpeed);
        }
    }

    currentStaggerGroup = (currentStaggerGroup + 1) % STAGGER_GROUPS;
}

fn moveTowards(position: *components.Position, target: rl.Vector2, deltaTime: f32) void {
    moveTowardsWithSpeed(position, target, deltaTime, 1.0);
}

fn moveTowardsWithSpeed(position: *components.Position, target: rl.Vector2, deltaTime: f32, speedMultiplier: f32) void {
    const speed = MOVEMENT_LEAP_FACTOR * speedMultiplier;
    position.x += (target.x - position.x) * speed * deltaTime;
    position.y += (target.y - position.y) * speed * deltaTime;
}

fn buildAvailableFlowersCache(world: *World, gridWidth: usize, gridHeight: usize) void {
    availableFlowerCount = 0;
    rottenFlowerCount = 0;
    cellStride = @min(gridWidth, grid_mod.MAX_WIDTH);
    cellRows = @min(gridHeight, grid_mod.MAX_WIDTH);
    @memset(cellEntry[0 .. cellStride * cellRows], NO_ENTRY);

    var iter = world.iterateFlowers();
    while (iter.next()) |entity| {
        if (availableFlowerCount >= MAX_AVAILABLE_FLOWERS and
            (!gardenerSweep or rottenFlowerCount >= MAX_ROTTEN_FLOWERS)) break;

        if (world.getFlowerGrowth(entity)) |growth| {
            // Rotten flowers feed the sweeper cache instead (Composting).
            if (growth.isRotten) {
                if (!gardenerSweep or rottenFlowerCount >= MAX_ROTTEN_FLOWERS) continue;
                if (world.getFlowerTargetCount(entity) > 0) continue;
                if (world.getGridPosition(entity)) |gridPos| {
                    rottenFlowers[rottenFlowerCount] = .{
                        .entity = entity,
                        .gridX = gridPos.x,
                        .gridY = gridPos.y,
                        .slots = 1,
                        .cell = 0,
                    };
                    rottenFlowerCount += 1;
                }
                continue;
            }
            if (availableFlowerCount >= MAX_AVAILABLE_FLOWERS) continue;
            if (growth.state != 4 or !growth.hasPollen) continue;

            const beesNearFlower = world.getFlowerTargetCount(entity);
            if (beesNearFlower >= MAX_BEES_PER_FLOWER) continue;

            if (world.getGridPosition(entity)) |gridPos| {
                if (world.getLifespan(entity)) |lifespan| {
                    if (lifespan.isDead()) continue;
                }
                const cx = @floor(gridPos.x);
                const cy = @floor(gridPos.y);
                if (cx < 0 or cy < 0 or cx >= @as(f32, @floatFromInt(cellStride)) or cy >= @as(f32, @floatFromInt(cellRows))) continue;
                const cell: usize = @as(usize, @intFromFloat(cy)) * cellStride + @as(usize, @intFromFloat(cx));
                if (cellEntry[cell] != NO_ENTRY) continue;

                // SUPER flowers span a 2x2 block anchored at gridPos; bees
                // should fly to the block's visual centre.
                const superOffset: f32 = if (growth.isSuper) 0.5 else 0.0;
                availableFlowers[availableFlowerCount] = .{
                    .entity = entity,
                    .gridX = gridPos.x + superOffset,
                    .gridY = gridPos.y + superOffset,
                    .slots = MAX_BEES_PER_FLOWER - beesNearFlower,
                    .cell = @intCast(cell),
                };
                cellEntry[cell] = @intCast(availableFlowerCount);
                availableFlowerCount += 1;
            }
        }
    }
}

const FlowerHit = struct {
    entity: Entity,
    gridX: f32,
    gridY: f32,
};

/// Mark every tile a flower (or the hive) sits on, then re-mark the cells
/// gardeners are already flying to plant.
fn buildOccupancy(world: *World) void {
    if (cellStride == 0 or cellRows == 0) return;
    const cells = cellStride * cellRows;
    @memset(cellOccupied[0..cells], false);
    @memset(cellSowClaimed[0..cells], false);

    const cols: i32 = @intCast(cellStride);
    const rows: i32 = @intCast(cellRows);
    var iter = world.iterateFlowers();
    while (iter.next()) |entity| {
        const gridPos = world.getGridPosition(entity) orelse continue;
        const gx: i32 = @intFromFloat(@floor(gridPos.x));
        const gy: i32 = @intFromFloat(@floor(gridPos.y));
        const span: i32 = if (world.getFlowerGrowth(entity)) |g| (if (g.isSuper) 2 else 1) else 1;
        var dy: i32 = 0;
        while (dy < span) : (dy += 1) {
            var dx: i32 = 0;
            while (dx < span) : (dx += 1) {
                const x = gx + dx;
                const y = gy + dy;
                if (x < 0 or y < 0 or x >= cols or y >= rows) continue;
                cellOccupied[@as(usize, @intCast(y)) * cellStride + @as(usize, @intCast(x))] = true;
            }
        }
    }
    const hive = cellIndexOf(cachedBeehiveGridX, cachedBeehiveGridY);
    if (hive) |h| cellOccupied[h] = true;

    for (world.bees.list.items(.ai)) |ai| {
        if (!ai.sowTarget) continue;
        if (cellIndexOf(ai.targetGridX, ai.targetGridY)) |c| cellSowClaimed[c] = true;
    }
}

/// Index into the cell tables for grid coordinates, or null when outside.
fn cellIndexOf(gridX: f32, gridY: f32) ?usize {
    if (cellStride == 0 or cellRows == 0) return null;
    const x = @floor(gridX);
    const y = @floor(gridY);
    if (x < 0 or y < 0 or x >= @as(f32, @floatFromInt(cellStride)) or y >= @as(f32, @floatFromInt(cellRows))) return null;
    return @as(usize, @intFromFloat(y)) * cellStride + @as(usize, @intFromFloat(x));
}

fn cellIsGap(cell: usize) bool {
    return !cellOccupied[cell] and !cellSowClaimed[cell];
}

const CellHit = struct { x: f32, y: f32 };

/// Nearest unclaimed empty tile: the scan square around the bee's own
/// tile first, then a handful of random probes across the meadow. Claims
/// the cell it returns.
fn findEmptyCell(beePosition: rl.Vector2) ?CellHit {
    if (cellStride == 0 or cellRows == 0) return null;
    const grid = utils.worldToGrid(beePosition, frameGridOffset, frameGridScale);
    const maxCol: f32 = @floatFromInt(cellStride - 1);
    const maxRow: f32 = @floatFromInt(cellRows - 1);
    const cx: i32 = @intFromFloat(std.math.clamp(@floor(grid.x), 0, maxCol));
    const cy: i32 = @intFromFloat(std.math.clamp(@floor(grid.y), 0, maxRow));
    const cols: i32 = @intCast(cellStride);
    const rows: i32 = @intCast(cellRows);

    var best: i32 = std.math.maxInt(i32);
    var bestCell: ?usize = null;
    var dy: i32 = -LOCAL_SEARCH_RADIUS;
    while (dy <= LOCAL_SEARCH_RADIUS) : (dy += 1) {
        const row = cy + dy;
        if (row < 0 or row >= rows) continue;
        var dx: i32 = -LOCAL_SEARCH_RADIUS;
        while (dx <= LOCAL_SEARCH_RADIUS) : (dx += 1) {
            const col = cx + dx;
            if (col < 0 or col >= cols) continue;
            const cell = @as(usize, @intCast(row)) * cellStride + @as(usize, @intCast(col));
            if (!cellIsGap(cell)) continue;
            const d = dx * dx + dy * dy;
            if (d < best) {
                best = d;
                bestCell = cell;
            }
        }
    }
    if (bestCell == null) {
        const cells = cellStride * cellRows;
        for (0..SOW_FALLBACK_PROBES) |_| {
            const cell: usize = @intCast(rl.getRandomValue(0, @intCast(cells - 1)));
            if (cellIsGap(cell)) {
                bestCell = cell;
                break;
            }
        }
    }
    const cell = bestCell orelse return null;
    cellSowClaimed[cell] = true;
    return .{
        .x = @floatFromInt(cell % cellStride),
        .y = @floatFromInt(cell / cellStride),
    };
}

/// Seed Scouts trip: fly to the claimed tile and plant on arrival (if it is
/// still empty), then dawdle and look for the next gap.
fn handleSowTrip(ctx: UpdateCtx, beeAI: *components.BeeAI, position: *components.Position, scaledDeltaTime: f32, nightSpeed: f32) !void {
    const targetPos = getWorldPosFromGrid(beeAI.targetGridX, beeAI.targetGridY, ctx.gridOffset, ctx.gridScale);
    const distance = rl.math.vector2Distance(position.toVector2(), targetPos);
    if (distance >= 5.0) {
        moveTowardsWithSpeed(position, targetPos, scaledDeltaTime, beeAI.beeType.getSpeedMultiplier() * nightSpeed);
        return;
    }

    if (cellIndexOf(beeAI.targetGridX, beeAI.targetGridY)) |cell| cellSowClaimed[cell] = false;
    const gx: i32 = @intFromFloat(@floor(beeAI.targetGridX));
    const gy: i32 = @intFromFloat(@floor(beeAI.targetGridY));
    if (gx >= 0 and gy >= 0 and gx < @as(i32, @intCast(ctx.gridWidth)) and gy < @as(i32, @intCast(ctx.gridHeight))) {
        const centerX: i32 = @intCast((ctx.gridWidth - 1) / 2);
        const centerY: i32 = @intCast((ctx.gridHeight - 1) / 2);
        if (!(gx == centerX and gy == centerY) and !ctx.world.hasFlowerAtGrid(gx, gy)) {
            try plantFlower(ctx.world, gx, gy, ctx.texturesRef);
            if (cellIndexOf(beeAI.targetGridX, beeAI.targetGridY)) |cell| cellOccupied[cell] = true;
        }
    }
    beeAI.sowTarget = false;
    beeAI.targetLocked = false;
    beeAI.targetEntity = null;
    beeAI.scatterTimer = @as(f32, @floatFromInt(rl.getRandomValue(4, 10))) / 10.0;
}

/// Plant a random flower on an empty cell (Seed Scouts trips and gardener
/// crossings both end here).
fn plantFlower(world: *World, gridX: i32, gridY: i32, texturesRef: Textures) !void {
    const flowerType = switch (rl.getRandomValue(1, 3)) {
        1 => Flowers.rose,
        2 => Flowers.dandelion,
        3 => Flowers.tulip,
        else => Flowers.rose,
    };

    const flowerTexture = texturesRef.getFlowerTexture(flowerType);
    const gridXf: f32 = @floatFromInt(gridX);
    const gridYf: f32 = @floatFromInt(gridY);

    const flowerEntity = try world.createEntity();
    try world.addGridPosition(flowerEntity, components.GridPosition.init(gridXf, gridYf));
    try world.addSprite(flowerEntity, components.Sprite.init(flowerTexture, 32, 32, 2));
    try world.addFlowerGrowth(flowerEntity, components.FlowerGrowth.init(textures.flowersToFlowerType(flowerType)));
    try world.addLifespan(flowerEntity, components.Lifespan.init(spawners.newFlowerLifespan(textures.flowersToFlowerType(flowerType))));
    world.registerFlowerAtGrid(gridX, gridY, flowerEntity);
    _ = try spawners.tryMergeSuperFlower(world, gridX, gridY);
}

/// Nearest flower with a free slot: first among the cells around the bee's
/// own tile, else the nearest of a bounded random sample of the cache.
fn findNearestFlowerFromCache(beePosition: rl.Vector2) ?FlowerHit {
    if (availableFlowerCount == 0) return null;

    var best: f32 = std.math.floatMax(f32);
    var bestIndex: ?usize = null;

    if (cellStride > 0 and cellRows > 0) {
        const grid = utils.worldToGrid(beePosition, frameGridOffset, frameGridScale);
        const maxCol: f32 = @floatFromInt(cellStride - 1);
        const maxRow: f32 = @floatFromInt(cellRows - 1);
        const cx: i32 = @intFromFloat(std.math.clamp(@floor(grid.x), 0, maxCol));
        const cy: i32 = @intFromFloat(std.math.clamp(@floor(grid.y), 0, maxRow));
        const cols: i32 = @intCast(cellStride);
        const rows: i32 = @intCast(cellRows);

        var dy: i32 = -LOCAL_SEARCH_RADIUS;
        while (dy <= LOCAL_SEARCH_RADIUS) : (dy += 1) {
            const row = cy + dy;
            if (row < 0 or row >= rows) continue;
            const rowBase: usize = @as(usize, @intCast(row)) * cellStride;
            var dx: i32 = -LOCAL_SEARCH_RADIUS;
            while (dx <= LOCAL_SEARCH_RADIUS) : (dx += 1) {
                const col = cx + dx;
                if (col < 0 or col >= cols) continue;
                const entry = cellEntry[rowBase + @as(usize, @intCast(col))];
                if (entry == NO_ENTRY) continue;
                const d = rl.math.vector2DistanceSqr(availableFlowerWorldPos[entry], beePosition);
                if (d < best) {
                    best = d;
                    bestIndex = entry;
                }
            }
        }
    }

    if (bestIndex == null) {
        const n = availableFlowerCount;
        const scan = @min(n, FALLBACK_SCAN);
        const start: usize = if (n > scan) @intCast(rl.getRandomValue(0, @intCast(n - 1))) else 0;
        for (0..scan) |k| {
            var i = start + k;
            if (i >= n) i -= n;
            const d = rl.math.vector2DistanceSqr(availableFlowerWorldPos[i], beePosition);
            if (d < best) {
                best = d;
                bestIndex = i;
            }
        }
    }

    const index = bestIndex orelse return null;
    return claimAvailableFlower(index);
}

/// Take one slot on a cache entry; entries with no slots left leave the
/// cache (and the cell index) until the next rebuild.
fn claimAvailableFlower(index: usize) FlowerHit {
    const flower = &availableFlowers[index];
    const hit = FlowerHit{ .entity = flower.entity, .gridX = flower.gridX, .gridY = flower.gridY };
    flower.slots -= 1;
    if (flower.slots == 0) {
        cellEntry[flower.cell] = NO_ENTRY;
        availableFlowerCount -= 1;
        const last = availableFlowerCount;
        if (index != last) {
            availableFlowers[index] = availableFlowers[last];
            availableFlowerWorldPos[index] = availableFlowerWorldPos[last];
            cellEntry[availableFlowers[index].cell] = @intCast(index);
        }
    }
    return hit;
}

/// Linear nearest-neighbour over a small cache (the rotten list).
fn findNearestFromCache(beePosition: rl.Vector2, flowers: []AvailableFlower, worldPos: []rl.Vector2, count: *usize) ?FlowerHit {
    var best: f32 = std.math.floatMax(f32);
    var bestIndex: ?usize = null;

    for (0..count.*) |i| {
        const d = rl.math.vector2DistanceSqr(worldPos[i], beePosition);
        if (d < best) {
            best = d;
            bestIndex = i;
        }
    }

    const index = bestIndex orelse return null;
    const flower = &flowers[index];
    const hit = FlowerHit{ .entity = flower.entity, .gridX = flower.gridX, .gridY = flower.gridY };
    // The caller locks the target right away (incrementing the world count);
    // mirror it locally so saturated flowers leave the scan until the next
    // cache rebuild instead of costing a HashMap lookup per bee per entry.
    flower.slots -= 1;
    if (flower.slots == 0) {
        count.* -= 1;
        flowers[index] = flowers[count.*];
        worldPos[index] = worldPos[count.*];
    }
    return hit;
}

fn findBeehive(world: *World) ?Entity {
    var iter = world.entityToBeehive.keyIterator();
    if (iter.next()) |entity| return entity.*;
    return null;
}

fn getWorldPosFromGrid(gridX: f32, gridY: f32, offset: rl.Vector2, gridScale: f32) rl.Vector2 {
    const tileWidth: f32 = 32;
    const tileHeight: f32 = 32;
    const flowerWidth: f32 = 32;
    const flowerHeight: f32 = 32;
    const flowerScale: f32 = 2;

    const tilePosition = utils.isoToXY(gridX, gridY, tileWidth, tileHeight, offset.x, offset.y, gridScale);
    const effectiveScale = flowerScale * (gridScale / 3.0);

    const tileTotalWidth = 32 * gridScale;
    const tileTotalHeight = 32 * gridScale;

    return rl.Vector2.init(
        tilePosition.x + (tileTotalWidth - flowerWidth * effectiveScale) / 2.0,
        tilePosition.y + (tileTotalHeight * 0.25) - (flowerHeight * effectiveScale),
    );
}

/// True when a screen position lies more than WANDER_MARGIN_TILES outside
/// the meadow.
fn isOffMeadow(position: rl.Vector2) bool {
    if (frameGridWidth == 0 or frameGridHeight == 0) return false;
    const grid = utils.worldToGrid(position, frameGridOffset, frameGridScale);
    const maxX = @as(f32, @floatFromInt(frameGridWidth)) + WANDER_MARGIN_TILES;
    const maxY = @as(f32, @floatFromInt(frameGridHeight)) + WANDER_MARGIN_TILES;
    return grid.x < -WANDER_MARGIN_TILES or grid.y < -WANDER_MARGIN_TILES or grid.x > maxX or grid.y > maxY;
}

fn performRandomWalk(beeAI: *components.BeeAI, position: *components.Position, deltaTime: f32) void {
    const wanderSpeed: f32 = 50.0;
    const wanderChangeInterval: f32 = 1.0;

    beeAI.wanderChangeTimer += deltaTime;

    if (beeAI.wanderChangeTimer >= wanderChangeInterval) {
        beeAI.wanderChangeTimer = 0;
        const jitter = @as(f32, @floatFromInt(rl.getRandomValue(-30, 30))) * std.math.pi / 180.0;
        if (isOffMeadow(position.toVector2())) {
            // Strayed past the rim: head back toward the hive.
            beeAI.wanderAngle = std.math.atan2(frameBeehivePos.y - position.y, frameBeehivePos.x - position.x) + jitter;
        } else {
            beeAI.wanderAngle += jitter;
        }
    }

    position.x += @cos(beeAI.wanderAngle) * wanderSpeed * deltaTime;
    position.y += @sin(beeAI.wanderAngle) * wanderSpeed * deltaTime;
}

/// Percent chance a gardener plants a flower on each fresh empty cell it
/// crosses. Raised by the Green Thumb tree node (see game.zig).
pub var gardenerPlantChance: i32 = GARDENER_BASE_CHANCE;
pub const GARDENER_BASE_CHANCE: i32 = 20;
pub const GARDENER_CHANCE_PER_LEVEL: i32 = 10;

/// Planting chance for a simulated gardener that stands for `weight` colony
/// gardeners: the chance that at least one of them plants (1 - (1-p)^w).
/// Exact at weight 1, so small colonies are untouched.
pub fn effectivePlantChance(percent: i32, weight: f32) i32 {
    if (weight <= 1.0 or percent <= 0 or percent >= 100) return percent;
    const p = @as(f32, @floatFromInt(percent)) / 100.0;
    const q = 1.0 - std.math.pow(f32, 1.0 - p, weight);
    return @intFromFloat(@round(std.math.clamp(q, p, 1.0) * 100.0));
}

test "representative gardeners plant on behalf of the bees they stand for" {
    try std.testing.expectEqual(@as(i32, 20), effectivePlantChance(20, 1.0));
    try std.testing.expectEqual(@as(i32, 20), effectivePlantChance(20, 0.5));
    try std.testing.expectEqual(@as(i32, 36), effectivePlantChance(20, 2.0));
    try std.testing.expectEqual(@as(i32, 99), effectivePlantChance(20, 20.0));
    try std.testing.expectEqual(@as(i32, 100), effectivePlantChance(20, 1000.0));
    try std.testing.expectEqual(@as(i32, 100), effectivePlantChance(100, 3.0));
    try std.testing.expectEqual(@as(i32, 0), effectivePlantChance(0, 3.0));
}

/// Composting node: gardeners clear rotten flowers on cells they cross.
pub var gardenerCompost: bool = false;

/// Rotten flowers cleared by gardeners (Composting) since the
/// game last drained it (achievements / lifetime stats).
pub var rottenClearedPending: u32 = 0;

pub fn takeRottenCleared() u32 {
    const n = rottenClearedPending;
    rottenClearedPending = 0;
    return n;
}

/// Composting also sends gardeners hunting for rotten flowers (instead of
/// only clearing rot they happen to cross).
pub var gardenerSweep: bool = false;

/// Seed Scouts node: idle gardeners seek out empty tiles and plant them.
pub var gardenerSow: bool = false;

/// Night penalty: at deep night bees produce half honey and fly slower,
/// ramping smoothly through dusk/dawn via the sky's night factor. The
/// repeatable Night Shift tree node buys the penalty off in quarters.
pub const NIGHT_HONEY_PENALTY: f32 = 0.5;
pub const NIGHT_SPEED_PENALTY: f32 = 0.25;
pub const NIGHT_SHIFT_MAX_LEVEL: u16 = 4;

/// Fraction of the night penalty still active: 1 = no Night Shift levels,
/// 0 = node maxed. Set from the tree by game.zig (purchase/load/reset).
pub var nightPenaltyScale: f32 = 1.0;

pub fn nightPenaltyScaleForLevel(level: u16) f32 {
    const lvl: f32 = @floatFromInt(@min(level, NIGHT_SHIFT_MAX_LEVEL));
    return 1.0 - lvl / @as(f32, @floatFromInt(NIGHT_SHIFT_MAX_LEVEL));
}

/// Saddlebags node: flowers a bee visits per trip before flying home
/// (game.zig sets it from the tree level on purchase, reset and load).
pub var bagCapacity: u8 = 1;

pub fn bagCapacityForLevel(level: u16) u8 {
    return @intCast(@min(1 + @as(u32, level), std.math.maxInt(u8)));
}

/// Tailwind node: every bee's flight speed multiplier (game.zig sets it
/// from the tree level on purchase, reset and load).
pub var beeSpeedMul: f32 = 1.0;
pub const BEE_SPEED_PER_LEVEL: f32 = 1.15;

pub fn beeSpeedMulForLevel(level: u16) f32 {
    return std.math.pow(f32, BEE_SPEED_PER_LEVEL, @floatFromInt(level));
}

/// Honey multiplier at night factor `night` under the current penalty scale.
pub fn nightHoneyMul(night: f32) f32 {
    return 1.0 - NIGHT_HONEY_PENALTY * nightPenaltyScale * night;
}

/// Bee speed multiplier at night factor `night` under the current penalty scale.
pub fn nightSpeedMul(night: f32) f32 {
    return 1.0 - NIGHT_SPEED_PENALTY * nightPenaltyScale * night;
}

/// Deep-night honey multiplier at a given Night Shift level (tree tooltip).
pub fn nightHoneyMulForLevel(level: u16) f32 {
    return 1.0 - NIGHT_HONEY_PENALTY * nightPenaltyScaleForLevel(level);
}

test "night penalty ramps with the night factor and Night Shift buys it off" {
    nightPenaltyScale = 1.0;
    defer nightPenaltyScale = 1.0;
    try std.testing.expectApproxEqRel(@as(f32, 1.0), nightHoneyMul(0.0), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), nightHoneyMul(1.0), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.75), nightHoneyMul(0.5), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), nightSpeedMul(0.0), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.75), nightSpeedMul(1.0), 1e-6);

    // Each level removes a quarter of the penalty; level 4 removes it all.
    try std.testing.expectApproxEqRel(@as(f32, 0.5), nightHoneyMulForLevel(0), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.625), nightHoneyMulForLevel(1), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.75), nightHoneyMulForLevel(2), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 0.875), nightHoneyMulForLevel(3), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), nightHoneyMulForLevel(4), 1e-6);

    nightPenaltyScale = nightPenaltyScaleForLevel(4);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), nightHoneyMul(1.0), 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), nightSpeedMul(1.0), 1e-6);
}

pub fn gardenerChanceForLevel(level: u16) i32 {
    return @min(100, GARDENER_BASE_CHANCE + GARDENER_CHANCE_PER_LEVEL * @as(i32, level));
}

/// Gardener flies over a rotten flower: clear it so the cell can regrow.
fn handleComposting(world: *World, beeAI: *components.BeeAI, position: *components.Position, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize) !void {
    const gridPos = utils.worldToGrid(position.toVector2(), gridOffset, gridScale);
    const gridX: i32 = @intFromFloat(@floor(gridPos.x));
    const gridY: i32 = @intFromFloat(@floor(gridPos.y));
    if (gridX == beeAI.lastCompostX and gridY == beeAI.lastCompostY) return;
    beeAI.lastCompostX = gridX;
    beeAI.lastCompostY = gridY;
    if (gridX < 0 or gridY < 0 or gridX >= @as(i32, @intCast(gridWidth)) or gridY >= @as(i32, @intCast(gridHeight))) return;

    const flowerEntity = world.getFlowerAtGrid(gridX, gridY) orelse return;
    const growth = world.getFlowerGrowth(flowerEntity) orelse return;
    if (growth.isRotten) {
        try lifespan_system.removeFlower(world, flowerEntity);
        rottenClearedPending += 1;
    }
}

fn handlePollination(world: *World, beeAI: *components.BeeAI, position: *components.Position, gridOffset: rl.Vector2, gridScale: f32, gridWidth: usize, gridHeight: usize, texturesRef: Textures) !void {
    if (!beeAI.beeType.canSpawnFlowers()) return;

    const gridPos = utils.worldToGrid(position.toVector2(), gridOffset, gridScale);
    const gridX: i32 = @intFromFloat(@floor(gridPos.x));
    const gridY: i32 = @intFromFloat(@floor(gridPos.y));

    if (gridX == beeAI.lastGridX and gridY == beeAI.lastGridY) return;

    beeAI.lastGridX = gridX;
    beeAI.lastGridY = gridY;

    if (gridX < 0 or gridY < 0 or gridX >= @as(i32, @intCast(gridWidth)) or gridY >= @as(i32, @intCast(gridHeight))) return;

    const centerX: i32 = @intCast((gridWidth - 1) / 2);
    const centerY: i32 = @intCast((gridHeight - 1) / 2);
    if (gridX == centerX and gridY == centerY) return;

    if (!world.hasFlowerAtGrid(gridX, gridY)) {
        if (rl.getRandomValue(1, 100) <= framePlantChance) {
            try plantFlower(world, gridX, gridY, texturesRef);
        }
    }
}
