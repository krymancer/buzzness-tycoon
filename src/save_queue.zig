//! Owns one immutable autosave snapshot while disk I/O runs off the game loop.
//! Explicit saves drain the queue first, so an older autosave can never replace
//! a newer pause/exit/ascension save. Unsupported concurrency falls back safely.
const std = @import("std");
const save = @import("save.zig");

pub const Queue = struct {
    const Job = struct {
        data: save.Data,
        done: std.atomic.Value(bool) = .init(false),
    };
    job: ?*Job = null,
    future: ?std.Io.Future(anyerror!void) = null,

    fn write(io: std.Io, path: []const u8, job: *Job) anyerror!void {
        defer job.done.store(true, .release);
        try save.write(io, path, &job.data);
    }

    pub fn busy(self: *const Queue) bool {
        return if (self.job) |job| !job.done.load(.acquire) else false;
    }

    /// Takes ownership of data, including on failure. `path` must outlive finish.
    pub fn submit(self: *Queue, allocator: std.mem.Allocator, io: std.Io, path: []const u8, data: save.Data) !void {
        var owned = data;
        var transferred = false;
        defer if (!transferred) owned.deinit(allocator);
        try self.finish(allocator, io);
        const job = try allocator.create(Job);
        job.* = .{ .data = owned };
        const future = io.concurrent(write, .{ io, path, job }) catch {
            defer allocator.destroy(job);
            try save.write(io, path, &owned);
            return;
        };
        transferred = true;
        self.job = job;
        self.future = future;
    }

    pub fn finish(self: *Queue, allocator: std.mem.Allocator, io: std.Io) !void {
        const job = self.job orelse return;
        defer {
            job.data.deinit(allocator);
            allocator.destroy(job);
            self.job = null;
            self.future = null;
        }
        try self.future.?.await(io);
    }
};

test "queued snapshots finish in order and preserve every flower type" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var pathBuf: [128]u8 = undefined;
    const path = try std.fmt.bufPrint(&pathBuf, ".zig-cache/tmp/{s}/save.txt", .{temp.sub_path});
    var queue: Queue = .{};
    defer queue.finish(std.testing.allocator, std.testing.io) catch {};
    try queue.submit(std.testing.allocator, std.testing.io, path, .{ .honey = 10 });
    var data: save.Data = .{ .honey = 25 };
    for (0..@import("ecs/components.zig").FlowerType.count) |i| {
        try data.flowers.append(std.testing.allocator, .{
            .flower_type = @intCast(i),
            .x = @intCast(i),
            .y = 0,
            .state = 4,
            .growth_time_alive = 0,
            .growth_rate = 1,
            .growth_threshold = 35,
            .has_pollen = true,
            .pollen_cooldown = 0,
            .pollen_multiplier = 1,
            .lifespan_time_alive = 0,
            .lifespan_total_time_alive = 0,
            .lifespan_time_span = 100,
        });
    }
    try queue.submit(std.testing.allocator, std.testing.io, path, data);
    try queue.finish(std.testing.allocator, std.testing.io);
    var restored = try save.read(std.testing.allocator, std.testing.io, path);
    defer restored.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(f32, 25), restored.honey);
    try std.testing.expectEqual(@import("ecs/components.zig").FlowerType.count, restored.flowers.items.len);
    for (restored.flowers.items, 0..) |flower, i| try std.testing.expectEqual(@as(u8, @intCast(i)), flower.flower_type);
}
