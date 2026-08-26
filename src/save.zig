const std = @import("std");
const achievements = @import("achievements.zig");

pub const VERSION: u32 = 1;
pub const MAX_UPGRADES: usize = 64;
pub const MAX_SHOP_ITEMS: usize = 16;
pub const MAX_FLOWERS: usize = 100_000;
pub const MAX_BEES_PER_TYPE: u32 = 100_000;
pub const MAX_BEES: usize = 4 * @as(usize, MAX_BEES_PER_TYPE);
pub const MAX_BEE_CELLS: usize = 131_072;

/// Bees aggregated per grid cell (type + tile + count). Tile coordinates are
/// invariant to the camera pan/zoom and window size at save time, and the
/// line count is bounded by occupied cells — a colony of any size stays a
/// few KB in the save.
pub const BeeCell = struct {
    bee_type: u8,
    x: i32,
    y: i32,
    count: u32,
};

pub const Flower = struct {
    flower_type: u8,
    x: i32,
    y: i32,
    state: f32,
    growth_time_alive: f32,
    growth_rate: f32,
    growth_threshold: f32,
    has_pollen: bool,
    pollen_cooldown: f32,
    pollen_multiplier: f32,
    lifespan_time_alive: f32,
    lifespan_total_time_alive: f32,
    lifespan_time_span: f32,
    is_super: bool = false,
    is_rotten: bool = false,
};

pub const Data = struct {
    language: u8 = 0,
    ui_scale: f32 = 1,
    window_mode: u8 = 1, // settings.WindowMode (1 = borderless)
    music_volume: f32 = 0.7,
    fx_volume: f32 = 0.7,
    cursor_snap: bool = true,
    honey: f32 = 100,
    honey_capacity: f32 = 500,
    storage_level: u32 = 1,
    honey_per_sec: f32 = 0,
    growth_cooldown: f32 = 0,
    growth_max_cooldown: f32 = 10,
    growth_level: u32 = 1,
    beehive_factor: f32 = 1,
    beehive_upgrade_cost: f32 = 20,
    grid_width: usize = 17,
    grid_height: usize = 17,
    royal_jelly: u32 = 0,
    this_run_honey: f32 = 0,
    prestige_unlocked: bool = false,
    /// Royal Jelly spent in the prestige shop (absent in older saves).
    jelly_spent: u32 = 0,
    /// Prestige shop level per item, indexed by prestige.ShopItem.
    shop_levels: [MAX_SHOP_ITEMS]u16 = [_]u16{0} ** MAX_SHOP_ITEMS,
    // Legacy labs line. aura_multiplier is derived from tree levels on load;
    // the three cooldown slots belonged to the removed Burst/Bloom labs and
    // are written as 0 to keep the line shape stable.
    aura_multiplier: f32 = 1,
    burst_remaining: f32 = 0,
    burst_cooldown: f32 = 0,
    bloom_cooldown: f32 = 0,
    purchased: [MAX_UPGRADES]bool = [_]bool{false} ** MAX_UPGRADES,
    /// Level per upgrade (repeatable nodes). 0/absent with purchased=true means level 1.
    levels: [MAX_UPGRADES]u16 = [_]u16{0} ** MAX_UPGRADES,
    bee_counts: [4]u32 = [_]u32{0} ** 4,
    /// Per-cell bee lines; empty in saves written before positions were
    /// persisted (loaders fall back to bee_counts).
    bee_cells: std.ArrayList(BeeCell) = .empty,
    flowers: std.ArrayList(Flower) = .empty,
    /// Lifetime counters (`stat <api> <value>` lines) and unlocked
    /// achievements (`achievement <api>` lines). Both are profile-level:
    /// they survive prestige and New Game. Absent in older saves.
    stats: achievements.Stats = .{},
    achievements: [achievements.COUNT]bool = @splat(false),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.bee_cells.deinit(allocator);
        self.flowers.deinit(allocator);
    }
};

pub fn path(allocator: std.mem.Allocator, env: *std.process.Environ.Map) ![]u8 {
    if (env.get("BT_SAVE_PATH")) |override| return allocator.dupe(u8, override);

    if (@import("builtin").os.tag == .windows) {
        if (env.get("LOCALAPPDATA")) |base| {
            return std.fs.path.join(allocator, &.{ base, "Buzzness Tycoon", "save.txt" });
        }
    } else if (@import("builtin").os.tag == .macos) {
        if (env.get("HOME")) |base| {
            return std.fs.path.join(allocator, &.{ base, "Library", "Application Support", "Buzzness Tycoon", "save.txt" });
        }
    } else {
        if (env.get("XDG_DATA_HOME")) |base| {
            return std.fs.path.join(allocator, &.{ base, "buzzness-tycoon", "save.txt" });
        }
        if (env.get("HOME")) |base| {
            return std.fs.path.join(allocator, &.{ base, ".local", "share", "buzzness-tycoon", "save.txt" });
        }
    }

    return allocator.dupe(u8, "buzzness-tycoon-save.txt");
}

pub fn write(io: std.Io, save_path: []const u8, data: *const Data) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, save_path, .{
        .make_path = true,
        .replace = true,
    });
    defer atomic.deinit(io);

    var buffer: [4096]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    const writer = &file_writer.interface;

    try writer.print("BUZZNESS_TYCOON {d}\n", .{VERSION});
    try writer.print("language {d}\n", .{data.language});
    try writer.print("ui_scale {d}\n", .{data.ui_scale});
    try writer.print("window_mode {d}\n", .{data.window_mode});
    // Legacy single-channel line first so older builds still restore a
    // volume, and so the split lines below win when this build reloads.
    try writer.print("volume {d}\n", .{@max(data.music_volume, data.fx_volume)});
    try writer.print("music_volume {d}\n", .{data.music_volume});
    try writer.print("fx_volume {d}\n", .{data.fx_volume});
    try writer.print("cursor_snap {d}\n", .{@intFromBool(data.cursor_snap)});
    try writer.print("resources {d} {d} {d} {d} {d} {d} {d}\n", .{
        data.honey,
        data.honey_capacity,
        data.storage_level,
        data.honey_per_sec,
        data.growth_cooldown,
        data.growth_max_cooldown,
        data.growth_level,
    });
    try writer.print("hive {d} {d}\n", .{ data.beehive_factor, data.beehive_upgrade_cost });
    try writer.print("grid {d} {d}\n", .{ data.grid_width, data.grid_height });
    try writer.print("prestige {d} {d} {d}\n", .{ data.royal_jelly, data.this_run_honey, @intFromBool(data.prestige_unlocked) });
    try writer.print("labs {d} {d} {d} {d}\n", .{ data.aura_multiplier, data.burst_remaining, data.burst_cooldown, data.bloom_cooldown });
    try writer.print("jelly_spent {d}\n", .{data.jelly_spent});
    for (data.shop_levels, 0..) |lvl, id| {
        if (lvl > 0) try writer.print("shop {d} {d}\n", .{ id, lvl });
    }
    inline for (@typeInfo(achievements.Stat).@"enum".fields) |f| {
        const stat: achievements.Stat = @enumFromInt(f.value);
        try writer.print("stat {s} {d}\n", .{ stat.api(), data.stats.get(stat) });
    }
    for (data.achievements, 0..) |unlocked, i| {
        if (unlocked) try writer.print("achievement {s}\n", .{achievements.DEFS[i].api});
    }

    for (data.purchased, 0..) |purchased, id| {
        if (!purchased) continue;
        try writer.print("upgrade {d}\n", .{id});
        if (data.levels[id] > 1) try writer.print("level {d} {d}\n", .{ id, data.levels[id] });
    }
    // Counts are written alongside the per-bee lines so older builds (which
    // only know "bees") still restore the population.
    for (data.bee_counts, 0..) |count, bee_type| {
        if (count > 0) try writer.print("bees {d} {d}\n", .{ bee_type, count });
    }
    for (data.bee_cells.items) |cell| {
        try writer.print("bee {d} {d} {d} {d}\n", .{ cell.bee_type, cell.x, cell.y, cell.count });
    }
    for (data.flowers.items) |flower| {
        try writer.print("flower {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d}\n", .{
            flower.flower_type,
            flower.x,
            flower.y,
            flower.state,
            flower.growth_time_alive,
            flower.growth_rate,
            flower.growth_threshold,
            @intFromBool(flower.has_pollen),
            flower.pollen_cooldown,
            flower.pollen_multiplier,
            flower.lifespan_time_alive,
            flower.lifespan_total_time_alive,
            flower.lifespan_time_span,
            @intFromBool(flower.is_super),
            @intFromBool(flower.is_rotten),
        });
    }
    try writer.writeAll("END\n");

    try file_writer.flush();
    try atomic.file.sync(io);
    try atomic.replace(io);
}

pub fn read(allocator: std.mem.Allocator, io: std.Io, save_path: []const u8) !Data {
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, save_path, allocator, .limited(32 * 1024 * 1024));
    defer allocator.free(contents);

    var data = Data{};
    errdefer data.deinit(allocator);
    var saw_header = false;
    var saw_end = false;
    var saw_resources = false;
    var saw_hive = false;
    var saw_grid = false;
    var saw_prestige = false;
    var saw_labs = false;

    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const key = tokens.next() orelse continue;

        if (std.mem.eql(u8, key, "END")) {
            saw_end = true;
        } else if (std.mem.eql(u8, key, "BUZZNESS_TYCOON")) {
            const version = try parse(u32, tokens.next());
            if (version != VERSION) return error.UnsupportedSaveVersion;
            saw_header = true;
        } else if (std.mem.eql(u8, key, "language")) {
            data.language = try parse(u8, tokens.next());
        } else if (std.mem.eql(u8, key, "ui_scale")) {
            data.ui_scale = try parse(f32, tokens.next());
        } else if (std.mem.eql(u8, key, "window_mode")) {
            data.window_mode = try parse(u8, tokens.next());
        } else if (std.mem.eql(u8, key, "volume")) {
            // Pre-split saves: one master volume seeds both channels.
            const v = try parse(f32, tokens.next());
            data.music_volume = v;
            data.fx_volume = v;
        } else if (std.mem.eql(u8, key, "music_volume")) {
            data.music_volume = try parse(f32, tokens.next());
        } else if (std.mem.eql(u8, key, "fx_volume")) {
            data.fx_volume = try parse(f32, tokens.next());
        } else if (std.mem.eql(u8, key, "cursor_snap")) {
            data.cursor_snap = (try parse(u8, tokens.next())) != 0;
        } else if (std.mem.eql(u8, key, "resources")) {
            saw_resources = true;
            data.honey = try parse(f32, tokens.next());
            data.honey_capacity = try parse(f32, tokens.next());
            data.storage_level = try parse(u32, tokens.next());
            data.honey_per_sec = try parse(f32, tokens.next());
            data.growth_cooldown = try parse(f32, tokens.next());
            data.growth_max_cooldown = try parse(f32, tokens.next());
            data.growth_level = try parse(u32, tokens.next());
        } else if (std.mem.eql(u8, key, "hive")) {
            saw_hive = true;
            data.beehive_factor = try parse(f32, tokens.next());
            data.beehive_upgrade_cost = try parse(f32, tokens.next());
        } else if (std.mem.eql(u8, key, "grid")) {
            saw_grid = true;
            data.grid_width = try parse(usize, tokens.next());
            data.grid_height = try parse(usize, tokens.next());
        } else if (std.mem.eql(u8, key, "prestige")) {
            saw_prestige = true;
            data.royal_jelly = try parse(u32, tokens.next());
            data.this_run_honey = try parse(f32, tokens.next());
            data.prestige_unlocked = (try parse(u8, tokens.next())) != 0;
        } else if (std.mem.eql(u8, key, "labs")) {
            saw_labs = true;
            data.aura_multiplier = try parse(f32, tokens.next());
            data.burst_remaining = try parse(f32, tokens.next());
            data.burst_cooldown = try parse(f32, tokens.next());
            data.bloom_cooldown = try parse(f32, tokens.next());
        } else if (std.mem.eql(u8, key, "jelly_spent")) {
            data.jelly_spent = try parse(u32, tokens.next());
        } else if (std.mem.eql(u8, key, "shop")) {
            const id = try parse(usize, tokens.next());
            const lvl = try parse(u16, tokens.next());
            if (id < data.shop_levels.len) data.shop_levels[id] = lvl;
        } else if (std.mem.eql(u8, key, "stat")) {
            // Unknown stat names (from a newer build) are skipped, not fatal.
            const stat_name = tokens.next() orelse return error.InvalidSave;
            const value = try parse(f64, tokens.next());
            if (achievements.Stat.fromApi(stat_name)) |stat| data.stats.set(stat, value);
        } else if (std.mem.eql(u8, key, "achievement")) {
            const api = tokens.next() orelse return error.InvalidSave;
            if (achievements.findByApi(api)) |id| data.achievements[@intFromEnum(id)] = true;
        } else if (std.mem.eql(u8, key, "upgrade")) {
            const id = try parse(usize, tokens.next());
            if (id < data.purchased.len) data.purchased[id] = true;
        } else if (std.mem.eql(u8, key, "level")) {
            const id = try parse(usize, tokens.next());
            const lvl = try parse(u16, tokens.next());
            if (id < data.levels.len) {
                data.levels[id] = lvl;
                if (lvl > 0) data.purchased[id] = true;
            }
        } else if (std.mem.eql(u8, key, "bee")) {
            if (data.bee_cells.items.len >= MAX_BEE_CELLS) return error.SaveTooLarge;
            const cell = BeeCell{
                .bee_type = try parse(u8, tokens.next()),
                .x = try parse(i32, tokens.next()),
                .y = try parse(i32, tokens.next()),
                .count = try parse(u32, tokens.next()),
            };
            if (cell.count <= MAX_BEES_PER_TYPE) try data.bee_cells.append(allocator, cell);
        } else if (std.mem.eql(u8, key, "bees")) {
            const bee_type = try parse(usize, tokens.next());
            const count = try parse(u32, tokens.next());
            if (bee_type < data.bee_counts.len and count <= MAX_BEES_PER_TYPE) data.bee_counts[bee_type] = count;
        } else if (std.mem.eql(u8, key, "flower")) {
            if (data.flowers.items.len >= MAX_FLOWERS) return error.SaveTooLarge;
            try data.flowers.append(allocator, .{
                .flower_type = try parse(u8, tokens.next()),
                .x = try parse(i32, tokens.next()),
                .y = try parse(i32, tokens.next()),
                .state = try parse(f32, tokens.next()),
                .growth_time_alive = try parse(f32, tokens.next()),
                .growth_rate = try parse(f32, tokens.next()),
                .growth_threshold = try parse(f32, tokens.next()),
                .has_pollen = (try parse(u8, tokens.next())) != 0,
                .pollen_cooldown = try parse(f32, tokens.next()),
                .pollen_multiplier = try parse(f32, tokens.next()),
                .lifespan_time_alive = try parse(f32, tokens.next()),
                .lifespan_total_time_alive = try parse(f32, tokens.next()),
                .lifespan_time_span = try parse(f32, tokens.next()),
                // Added after v1 shipped; absent in older saves.
                .is_super = parseOptionalFlag(tokens.next()),
                .is_rotten = parseOptionalFlag(tokens.next()),
            });
        }
    }

    if (!saw_header or !saw_end or !saw_resources or !saw_hive or !saw_grid or !saw_prestige or !saw_labs) {
        return error.InvalidSave;
    }
    return data;
}

fn parseOptionalFlag(token: ?[]const u8) bool {
    const value = token orelse return false;
    return !std.mem.eql(u8, value, "0");
}

fn parse(comptime T: type, token: ?[]const u8) !T {
    const value = token orelse return error.InvalidSave;
    return switch (@typeInfo(T)) {
        .float => std.fmt.parseFloat(T, value),
        .int => std.fmt.parseInt(T, value, 10),
        else => @compileError("unsupported save value type"),
    };
}

test "save data survives an atomic round trip" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var path_buffer: [128]u8 = undefined;
    const save_path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/save.txt", .{temp.sub_path});

    var original = Data{
        .language = 1,
        .music_volume = 0.9,
        .fx_volume = 0.25,
        .honey = 9_000_000,
        .beehive_factor = 128,
        .royal_jelly = 42,
        .this_run_honey = 1_250_000,
        .prestige_unlocked = true,
        .jelly_spent = 17,
        .grid_width = 23,
        .grid_height = 23,
    };
    defer original.deinit(std.testing.allocator);
    original.shop_levels[2] = 3;
    original.stats.lifetimeHoney = 2.5e12;
    original.stats.prestigeCount = 6;
    original.stats.maxBeesAlive = 12_345;
    original.achievements[@intFromEnum(achievements.Id.first_drop)] = true;
    original.achievements[@intFromEnum(achievements.Id.sticky_situation)] = true;
    original.purchased[19] = true;
    original.purchased[24] = true;
    original.levels[24] = 7;
    original.bee_counts[2] = 17;
    try original.bee_cells.append(std.testing.allocator, .{ .bee_type = 3, .x = 4, .y = -2, .count = 12345 });
    try original.flowers.append(std.testing.allocator, .{
        .flower_type = 1,
        .x = 4,
        .y = 8,
        .state = 4,
        .growth_time_alive = 3,
        .growth_rate = 2,
        .growth_threshold = 35,
        .has_pollen = true,
        .pollen_cooldown = 7,
        .pollen_multiplier = 3.5,
        .lifespan_time_alive = 10,
        .lifespan_total_time_alive = 20,
        .lifespan_time_span = 120,
        .is_super = true,
        .is_rotten = true,
    });

    try write(std.testing.io, save_path, &original);
    var restored = try read(std.testing.allocator, std.testing.io, save_path);
    defer restored.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f32, 0.9), restored.music_volume);
    try std.testing.expectEqual(@as(f32, 0.25), restored.fx_volume);
    try std.testing.expectEqual(@as(f32, 9_000_000), restored.honey);
    try std.testing.expectEqual(@as(f32, 128), restored.beehive_factor);
    try std.testing.expectEqual(@as(u32, 42), restored.royal_jelly);
    try std.testing.expectEqual(@as(u32, 17), restored.jelly_spent);
    try std.testing.expectEqual(@as(u16, 3), restored.shop_levels[2]);
    try std.testing.expectEqual(@as(u16, 0), restored.shop_levels[0]);
    try std.testing.expectEqual(@as(f64, 2.5e12), restored.stats.lifetimeHoney);
    try std.testing.expectEqual(@as(u32, 6), restored.stats.prestigeCount);
    try std.testing.expectEqual(@as(u32, 12_345), restored.stats.maxBeesAlive);
    try std.testing.expectEqual(@as(u32, 0), restored.stats.rottenCleared);
    try std.testing.expect(restored.achievements[@intFromEnum(achievements.Id.first_drop)]);
    try std.testing.expect(restored.achievements[@intFromEnum(achievements.Id.sticky_situation)]);
    try std.testing.expect(!restored.achievements[@intFromEnum(achievements.Id.dynasty)]);
    try std.testing.expect(restored.purchased[19]);
    try std.testing.expectEqual(@as(u16, 0), restored.levels[19]);
    try std.testing.expect(restored.purchased[24]);
    try std.testing.expectEqual(@as(u16, 7), restored.levels[24]);
    try std.testing.expectEqual(@as(u32, 17), restored.bee_counts[2]);
    try std.testing.expectEqual(@as(usize, 1), restored.bee_cells.items.len);
    try std.testing.expectEqual(@as(u8, 3), restored.bee_cells.items[0].bee_type);
    try std.testing.expectEqual(@as(i32, 4), restored.bee_cells.items[0].x);
    try std.testing.expectEqual(@as(i32, -2), restored.bee_cells.items[0].y);
    try std.testing.expectEqual(@as(u32, 12345), restored.bee_cells.items[0].count);
    try std.testing.expectEqual(@as(usize, 1), restored.flowers.items.len);
    try std.testing.expectEqual(@as(f32, 3.5), restored.flowers.items[0].pollen_multiplier);
    try std.testing.expect(restored.flowers.items[0].is_super);
    try std.testing.expect(restored.flowers.items[0].is_rotten);
}

test "flower lines without the is_super field still parse (old saves)" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var path_buffer: [128]u8 = undefined;
    const save_path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/save_old.txt", .{temp.sub_path});

    const old_save =
        "BUZZNESS_TYCOON 1\n" ++
        "volume 0.4\n" ++
        "resources 100 500 1 0 0 10 1\n" ++
        "hive 1 20\n" ++
        "grid 17 17\n" ++
        "prestige 0 0 0\n" ++
        "labs 1 0 0 0\n" ++
        "flower 1 4 8 4 3 2 35 1 7 3.5 10 20 120\n" ++
        "END\n";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = save_path, .data = old_save });

    var restored = try read(std.testing.allocator, std.testing.io, save_path);
    defer restored.deinit(std.testing.allocator);

    // A legacy master volume seeds both channels.
    try std.testing.expectEqual(@as(f32, 0.4), restored.music_volume);
    try std.testing.expectEqual(@as(f32, 0.4), restored.fx_volume);
    // No shop lines: nothing spent, nothing owned.
    try std.testing.expectEqual(@as(u32, 0), restored.jelly_spent);
    try std.testing.expectEqual(@as(u16, 0), restored.shop_levels[0]);
    try std.testing.expectEqual(@as(usize, 1), restored.flowers.items.len);
    try std.testing.expect(!restored.flowers.items[0].is_super);
    // Pre-position saves carry no per-cell bee lines; loaders fall back to counts.
    try std.testing.expectEqual(@as(usize, 0), restored.bee_cells.items.len);
    // No stat/achievement lines: fresh profile.
    try std.testing.expectEqual(@as(f64, 0), restored.stats.lifetimeHoney);
    try std.testing.expectEqual(@as(usize, 0), (achievements.Tracker{ .unlocked = restored.achievements }).unlockedCount());
}

test "unknown stat and achievement names are ignored" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var path_buffer: [128]u8 = undefined;
    const save_path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/save_future.txt", .{temp.sub_path});

    const future_save =
        "BUZZNESS_TYCOON 1\n" ++
        "resources 100 500 1 0 0 10 1\n" ++
        "hive 1 20\n" ++
        "grid 17 17\n" ++
        "prestige 0 0 0\n" ++
        "labs 1 0 0 0\n" ++
        "stat lifetime_honey 4200\n" ++
        "stat from_the_future 7\n" ++
        "achievement first_drop\n" ++
        "achievement from_the_future\n" ++
        "END\n";
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = save_path, .data = future_save });

    var restored = try read(std.testing.allocator, std.testing.io, save_path);
    defer restored.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(f64, 4200), restored.stats.lifetimeHoney);
    try std.testing.expect(restored.achievements[@intFromEnum(achievements.Id.first_drop)]);
    try std.testing.expectEqual(@as(usize, 1), (achievements.Tracker{ .unlocked = restored.achievements }).unlockedCount());
}
