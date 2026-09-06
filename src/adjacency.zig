//! Layout bonuses: what a flower earns from its neighbours and its place on
//! the meadow. Recomputed for the whole grid whenever the flower set changes
//! (World.flowerGen), so the bee AI reads one cached multiplier per cell.
//!
//! Adjacency is the 4 orthogonal neighbours. Rotten flowers count as empty.
//!
//! - Cluster: 3+ connected flowers of one type — +50% pollen each.
//! - Cross-pollination: a rose next to a tulip (or vice versa) — +25% both.
//! - Meadow tile: a flower whose neighbourhood (itself included) holds all
//!   three types — x2 pollen. Competes with Cluster on purpose.
//! - Hive gradient: +4% per ring of distance from the hive — the far edge
//!   is worth the flight.

const std = @import("std");
const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");
const FlowerType = components.FlowerType;
const grid_mod = @import("grid.zig");

pub const MAX: usize = grid_mod.MAX_WIDTH;
const CELLS: usize = MAX * MAX;
const NONE: u8 = 255;

pub const CLUSTER_MIN: u32 = 3;
pub const CLUSTER_MUL: f32 = 1.5;
pub const PAIR_MUL: f32 = 1.25;
pub const MEADOW_MUL: f32 = 2.0;
pub const GRADIENT_PER_RING: f32 = 0.04;

pub const Bonus = struct {
    cluster: bool = false,
    pair: bool = false,
    meadow: bool = false,
    /// Rings of distance from the hive (Chebyshev).
    rings: u16 = 0,

    pub fn multiplier(self: @This()) f32 {
        var m: f32 = 1.0 + GRADIENT_PER_RING * @as(f32, @floatFromInt(self.rings));
        if (self.cluster) m *= CLUSTER_MUL;
        if (self.pair) m *= PAIR_MUL;
        if (self.meadow) m *= MEADOW_MUL;
        return m;
    }

    pub fn any(self: @This()) bool {
        return self.cluster or self.pair or self.meadow or self.rings > 0;
    }
};

var typeAt: [CELLS]u8 = @splat(NONE);
var compOf: [CELLS]u32 = @splat(0);
var compSize: [CELLS]u32 = @splat(0);
var compCount: u32 = 0;
var bonus: [CELLS]Bonus = @splat(.{});
var builtGen: u64 = 0;
var builtW: usize = 0;
var builtH: usize = 0;
var hiveX: i32 = 0;
var hiveY: i32 = 0;

fn idx(x: i32, y: i32) ?usize {
    if (x < 0 or y < 0 or x >= @as(i32, @intCast(builtW)) or y >= @as(i32, @intCast(builtH))) return null;
    return @as(usize, @intCast(y)) * MAX + @as(usize, @intCast(x));
}

/// Rebuild when the flower set or the meadow changed; cheap otherwise.
pub fn refresh(world: *World, w: usize, h: usize) void {
    if (builtGen == world.flowerGen and builtW == w and builtH == h) return;
    rebuild(world, w, h);
}

pub fn invalidate() void {
    builtGen = 0;
}

/// Pollen multiplier for the flower on (x, y); 1 when nothing applies.
pub fn multiplierAt(x: i32, y: i32) f32 {
    const i = idx(x, y) orelse return 1.0;
    return bonus[i].multiplier();
}

pub fn bonusAt(x: i32, y: i32) Bonus {
    const i = idx(x, y) orelse return .{};
    return bonus[i];
}

/// Cluster id of the flower on (x, y) (0 when it isn't in a cluster), for
/// highlighting the whole cluster under the cursor.
pub fn clusterIdAt(x: i32, y: i32) u32 {
    const i = idx(x, y) orelse return 0;
    if (!bonus[i].cluster) return 0;
    return compOf[i];
}

pub fn ringsFromHive(x: i32, y: i32) u16 {
    return @intCast(@max(@abs(x - hiveX), @abs(y - hiveY)));
}

const OFFS = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

fn rebuild(world: *World, w: usize, h: usize) void {
    builtW = @min(w, MAX);
    builtH = @min(h, MAX);
    builtGen = world.flowerGen;
    hiveX = @intCast((builtW - 1) / 2);
    hiveY = @intCast((builtH - 1) / 2);
    @memset(&typeAt, NONE);
    @memset(&compOf, 0);
    compCount = 0;

    // Type map; a SUPER flower fills its 2x2 block.
    var it = world.iterateFlowers();
    while (it.next()) |entity| {
        const gp = world.getGridPosition(entity) orelse continue;
        const g = world.getFlowerGrowth(entity) orelse continue;
        if (g.isRotten) continue;
        const gx: i32 = @intFromFloat(@floor(gp.x));
        const gy: i32 = @intFromFloat(@floor(gp.y));
        const span: i32 = if (g.isSuper) 2 else 1;
        var dy: i32 = 0;
        while (dy < span) : (dy += 1) {
            var dx: i32 = 0;
            while (dx < span) : (dx += 1) {
                if (idx(gx + dx, gy + dy)) |i| typeAt[i] = @intFromEnum(g.flowerType);
            }
        }
    }

    // Connected components of one type (iterative flood fill).
    var stack: [CELLS]usize = undefined;
    for (0..builtH) |yy| {
        for (0..builtW) |xx| {
            const start = yy * MAX + xx;
            if (typeAt[start] == NONE or compOf[start] != 0) continue;
            compCount += 1;
            const id = compCount;
            var size: u32 = 0;
            var sp: usize = 0;
            stack[sp] = start;
            sp += 1;
            compOf[start] = id;
            while (sp > 0) {
                sp -= 1;
                const c = stack[sp];
                size += 1;
                const cx: i32 = @intCast(c % MAX);
                const cy: i32 = @intCast(c / MAX);
                for (OFFS) |o| {
                    const n = idx(cx + o[0], cy + o[1]) orelse continue;
                    if (typeAt[n] != typeAt[c] or compOf[n] != 0) continue;
                    compOf[n] = id;
                    stack[sp] = n;
                    sp += 1;
                }
            }
            compSize[id] = size;
        }
    }

    // Per-cell bonuses.
    for (0..builtH) |yy| {
        for (0..builtW) |xx| {
            const i = yy * MAX + xx;
            bonus[i] = .{};
            if (typeAt[i] == NONE) continue;
            const x: i32 = @intCast(xx);
            const y: i32 = @intCast(yy);
            bonus[i] = bonusFor(x, y, typeAt[i], compOf[i]);
        }
    }
}

/// Bonus for a flower of type `t` on (x, y) whose cluster id is `own`
/// (0 = not placed yet; then its would-be cluster is counted from the
/// neighbouring components, which is what the planting brush previews).
fn bonusFor(x: i32, y: i32, t: u8, own: u32) Bonus {
    var b = Bonus{ .rings = ringsFromHive(x, y) };
    var seen: [FlowerType.count]bool = @splat(false);
    seen[t] = true;
    var clusterSize: u32 = if (own != 0) compSize[own] else 1;
    var touched: [4]u32 = .{ 0, 0, 0, 0 };
    var touchedN: usize = 0;
    for (OFFS) |o| {
        const n = idx(x + o[0], y + o[1]) orelse continue;
        const nt = typeAt[n];
        if (nt == NONE) continue;
        seen[nt] = true;
        if (nt == t and own == 0) {
            // Preview: merge the distinct neighbouring components.
            const cid = compOf[n];
            var dup = false;
            for (touched[0..touchedN]) |tc| dup = dup or tc == cid;
            if (!dup) {
                touched[touchedN] = cid;
                touchedN += 1;
                clusterSize += compSize[cid];
            }
        }
        const rose: u8 = @intFromEnum(FlowerType.rose);
        const tulip: u8 = @intFromEnum(FlowerType.tulip);
        if ((t == rose and nt == tulip) or (t == tulip and nt == rose)) b.pair = true;
    }
    b.cluster = clusterSize >= CLUSTER_MIN;
    var variety: usize = 0;
    for (seen) |present| {
        if (present) variety += 1;
    }
    b.meadow = variety >= 3;
    return b;
}

/// What a flower of type `t` would earn on the empty cell (x, y) right now.
pub fn preview(x: i32, y: i32, t: FlowerType) Bonus {
    if (idx(x, y) == null) return .{};
    return bonusFor(x, y, @intFromEnum(t), 0);
}

// ---- tests ------------------------------------------------------------------

const rl = @import("raylib");

fn testFlower(world: *World, t: FlowerType, x: i32, y: i32) !u32 {
    const dummy = rl.Texture{ .id = 0, .width = 32, .height = 32, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    const e = try world.createEntity();
    try world.addGridPosition(e, components.GridPosition.init(@floatFromInt(x), @floatFromInt(y)));
    try world.addSprite(e, components.Sprite.init(dummy, 32, 32, 2));
    try world.addFlowerGrowth(e, components.FlowerGrowth.init(t));
    try world.addLifespan(e, components.Lifespan.init(100));
    world.registerFlowerAtGrid(x, y, e);
    return e;
}

test "cluster needs three connected of a kind; pairs and meadow tiles stack" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    // Hive at (8,8) on a 17x17 meadow. A row of roses at y=2: x=1,2 (pair
    // of two: no cluster), then x=3 makes three.
    _ = try testFlower(&world, .rose, 1, 2);
    _ = try testFlower(&world, .rose, 2, 2);
    refresh(&world, 17, 17);
    try std.testing.expect(!bonusAt(1, 2).cluster);
    try std.testing.expectEqual(@as(u16, 7), bonusAt(1, 2).rings);
    try std.testing.expectApproxEqRel(@as(f32, 1.28), multiplierAt(1, 2), 1e-5);
    // Preview: a third rose next door would complete the cluster.
    try std.testing.expect(preview(3, 2, .rose).cluster);
    try std.testing.expect(!preview(3, 2, .tulip).cluster);

    _ = try testFlower(&world, .rose, 3, 2);
    refresh(&world, 17, 17);
    try std.testing.expect(bonusAt(1, 2).cluster and bonusAt(2, 2).cluster and bonusAt(3, 2).cluster);
    try std.testing.expect(clusterIdAt(1, 2) != 0 and clusterIdAt(1, 2) == clusterIdAt(3, 2));

    // A tulip under the middle rose: cross-pollination for both, and the
    // rose's neighbourhood now has rose + tulip; a dandelion on the other
    // side makes it a meadow tile.
    _ = try testFlower(&world, .tulip, 2, 3);
    refresh(&world, 17, 17);
    try std.testing.expect(bonusAt(2, 2).pair and bonusAt(2, 3).pair);
    try std.testing.expect(!bonusAt(2, 2).meadow);
    _ = try testFlower(&world, .dandelion, 2, 1);
    refresh(&world, 17, 17);
    try std.testing.expect(bonusAt(2, 2).meadow);
    const b = bonusAt(2, 2);
    try std.testing.expect(b.cluster and b.pair and b.meadow);
    try std.testing.expectApproxEqRel(@as(f32, (1.0 + 0.04 * 6) * 1.5 * 1.25 * 2.0), b.multiplier(), 1e-5);
    // The rebuild is generation-driven: nothing changes without a spawn.
    const gen = builtGen;
    refresh(&world, 17, 17);
    try std.testing.expectEqual(gen, builtGen);
}

test "rotten flowers count as empty and the hive tile has no gradient" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();
    _ = try testFlower(&world, .rose, 4, 4);
    _ = try testFlower(&world, .rose, 5, 4);
    const rotten = try testFlower(&world, .rose, 6, 4);
    world.getFlowerGrowth(rotten).?.isRotten = true;
    invalidate();
    refresh(&world, 9, 9);
    try std.testing.expect(!bonusAt(4, 4).cluster);
    try std.testing.expectEqual(@as(u16, 0), ringsFromHive(4, 4));
    try std.testing.expectEqual(@as(f32, 1.0), bonusAt(6, 4).multiplier());
}
