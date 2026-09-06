//! Headless simulation benchmark — no window, no rendering.
//!
//!     zig build bench -Doptimize=ReleaseFast -- [bees] [grid] [frames]
//!
//! Builds a meadow of `grid` x `grid` tiles (default 41) with the hive in
//! the middle and flowers on ~40% of the cells, sets the colony to `bees`
//! (default 1,000,000; simulated up to bees.SIM_CAP, the rest dormant),
//! then runs `frames` (default 600) simulation ticks at 60 Hz and reports
//! the average tick time and the honey earned. Numbers here cover the
//! update side of the frame; drawing is capped at 32k sprites and is
//! measured in the game itself (BT_SHOW_DEBUG / -Dshow_debug).

const std = @import("std");
const rl = @import("raylib");
const World = @import("ecs/world.zig").World;
const components = @import("ecs/components.zig");
const bees_mod = @import("bees.zig");
const bee_ai_system = @import("ecs/systems/bee_ai_system.zig");
const flower_growth_system = @import("ecs/systems/flower_growth_system.zig");
const flower_spawning_system = @import("ecs/systems/flower_spawning_system.zig");
const lifespan_system = @import("ecs/systems/lifespan_system.zig");
const Resources = @import("resources.zig").Resources;
const labs_mod = @import("labs.zig");
const prestige_mod = @import("prestige.zig");
const Textures = @import("textures.zig").Textures;
const utils = @import("utils.zig");

const DT: f32 = 1.0 / 60.0;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const beeCount: u64 = if (args.next()) |a| try std.fmt.parseInt(u64, a, 10) else 1_000_000;
    const gridSize: usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 41;
    const frames: u32 = if (args.next()) |a| try std.fmt.parseInt(u32, a, 10) else 600;

    const gpa = init.gpa;
    var world = World.init(gpa);
    defer world.deinit();

    // Camera: the whole meadow at scale 1 on a 1080p-ish viewport.
    const scale: f32 = 1.0;
    const offset = utils.calculateCenteredGridOffset(gridSize, gridSize, 32, 32, scale, 1920, 1080);
    world.bees.meadow = .{ .offset = offset, .scale = scale, .width = gridSize, .height = gridSize };

    const dummy = rl.Texture{ .id = 0, .width = 32, .height = 32, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    const textures = Textures{ .bee = dummy, .rose = dummy, .dandelion = dummy, .tulip = dummy, .beehive = dummy, .roseGray = dummy, .dandelionGray = dummy, .tulipGray = dummy };

    const center: f32 = @floatFromInt((gridSize - 1) / 2);
    const hive = try world.createEntity();
    try world.addGridPosition(hive, components.GridPosition.init(center, center));
    try world.addBeehive(hive, components.Beehive.init());

    var flowerCount: usize = 0;
    for (0..gridSize) |i| {
        for (0..gridSize) |j| {
            const fi: f32 = @floatFromInt(i);
            const fj: f32 = @floatFromInt(j);
            if (fi == center and fj == center) continue;
            if (rl.getRandomValue(1, 100) > 40) continue;
            const e = try world.createEntity();
            try world.addGridPosition(e, components.GridPosition.init(fi, fj));
            try world.addSprite(e, components.Sprite.init(dummy, 32, 32, 2));
            var growth = components.FlowerGrowth.init(.rose);
            growth.state = 4;
            growth.hasPollen = rl.getRandomValue(0, 1) == 1;
            try world.addFlowerGrowth(e, growth);
            try world.addLifespan(e, components.Lifespan.init(1e9));
            world.registerFlowerAtGrid(@intCast(i), @intCast(j), e);
            flowerCount += 1;
        }
    }

    // A late-game mix: mostly workers, some of everything else.
    const perType = [4]u64{ beeCount * 85 / 100, beeCount * 5 / 100, beeCount * 5 / 100, beeCount * 5 / 100 };
    for (perType, 0..) |n, t| {
        world.bees.setPopulation(@enumFromInt(t), @intCast(@min(n, bees_mod.MAX_PER_TYPE)));
    }
    try world.rebalanceBees();

    // Late-game gardener nodes on, so the sowing/sweeping paths are timed too.
    bee_ai_system.gardenerCompost = true;
    bee_ai_system.gardenerSweep = true;
    bee_ai_system.gardenerSow = true;

    var resources = Resources.init();
    resources.honeyCapacity = std.math.floatMax(f32);
    const labs: labs_mod.LabState = .{};
    var prestige: prestige_mod.PrestigeState = .{};
    var honey: f32 = 0;

    const io = init.io;
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..frames) |_| {
        var frameHoney: f32 = 0;
        try lifespan_system.update(&world, DT);
        try flower_growth_system.update(&world, DT);
        try bee_ai_system.update(.{
            .world = &world,
            .deltaTime = DT,
            .gridOffset = offset,
            .gridScale = scale,
            .gridWidth = gridSize,
            .gridHeight = gridSize,
            .texturesRef = textures,
            .resources = &resources,
            .labs = &labs,
            .prestige = &prestige,
            .honeyFactor = 1.0,
            .nightFactor = 0.0,
            .frameHoneyGain = &frameHoney,
        });
        try flower_spawning_system.update(&world, DT, offset, scale, gridSize, gridSize, textures);
        try world.processDestroyQueue();
        honey += frameHoney;
    }
    const elapsed = start.durationTo(std.Io.Timestamp.now(io, .awake));
    const totalMs = @as(f64, @floatFromInt(elapsed.nanoseconds)) / 1e6;
    const perFrameMs = totalMs / @as(f64, @floatFromInt(frames));
    const seconds = @as(f64, @floatFromInt(frames)) * DT;

    std.debug.print(
        "bees {d} (simulated {d}, dormant {d})  grid {d}x{d}  flowers {d}\n" ++
            "{d} frames: {d:.2} ms/frame avg ({d:.0} sim FPS ceiling)\n" ++
            "honey {d:.0} over {d:.1}s of game time = {d:.1}/s\n",
        .{
            world.bees.total(),
            world.bees.list.len,
            world.bees.dormant(),
            gridSize,
            gridSize,
            world.entityToFlowerGrowth.count(),
            frames,
            perFrameMs,
            1000.0 / perFrameMs,
            honey,
            seconds,
            honey / @as(f32, @floatCast(seconds)),
        },
    );
}
