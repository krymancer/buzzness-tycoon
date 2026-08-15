const std = @import("std");

pub const VERSION: u32 = 1;
pub const MAX_UPGRADES: usize = 64;
pub const MAX_FLOWERS: usize = 100_000;
pub const MAX_BEES_PER_TYPE: u32 = 100_000;

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
};

pub const Data = struct {
    language: u8 = 0,
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
    aura_multiplier: f32 = 1,
    burst_remaining: f32 = 0,
    burst_cooldown: f32 = 0,
    bloom_cooldown: f32 = 0,
    purchased: [MAX_UPGRADES]bool = [_]bool{false} ** MAX_UPGRADES,
    bee_counts: [4]u32 = [_]u32{0} ** 4,
    flowers: std.ArrayList(Flower) = .empty,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
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

    for (data.purchased, 0..) |purchased, id| {
        if (purchased) try writer.print("upgrade {d}\n", .{id});
    }
    for (data.bee_counts, 0..) |count, bee_type| {
        if (count > 0) try writer.print("bees {d} {d}\n", .{ bee_type, count });
    }
    for (data.flowers.items) |flower| {
        try writer.print("flower {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d} {d}\n", .{
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
        } else if (std.mem.eql(u8, key, "upgrade")) {
            const id = try parse(usize, tokens.next());
            if (id < data.purchased.len) data.purchased[id] = true;
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
            });
        }
    }

    if (!saw_header or !saw_end or !saw_resources or !saw_hive or !saw_grid or !saw_prestige or !saw_labs) {
        return error.InvalidSave;
    }
    return data;
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
        .honey = 9_000_000,
        .beehive_factor = 128,
        .royal_jelly = 42,
        .this_run_honey = 1_250_000,
        .prestige_unlocked = true,
        .grid_width = 23,
        .grid_height = 23,
    };
    defer original.deinit(std.testing.allocator);
    original.purchased[19] = true;
    original.bee_counts[2] = 17;
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
    });

    try write(std.testing.io, save_path, &original);
    var restored = try read(std.testing.allocator, std.testing.io, save_path);
    defer restored.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(f32, 9_000_000), restored.honey);
    try std.testing.expectEqual(@as(f32, 128), restored.beehive_factor);
    try std.testing.expectEqual(@as(u32, 42), restored.royal_jelly);
    try std.testing.expect(restored.purchased[19]);
    try std.testing.expectEqual(@as(u32, 17), restored.bee_counts[2]);
    try std.testing.expectEqual(@as(usize, 1), restored.flowers.items.len);
    try std.testing.expectEqual(@as(f32, 3.5), restored.flowers.items[0].pollen_multiplier);
}
