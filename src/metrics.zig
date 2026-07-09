const std = @import("std");
const rl = @import("raylib");

fn isLeapYear(year: u64) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

pub const Metrics = struct {
    io: std.Io,
    file: ?std.Io.File,
    frameCounter: u32,
    lastLogTime: f64,

    const LOG_INTERVAL_SECONDS: f64 = 1.0;
    const SPIKE_THRESHOLD_MS: f32 = 33.0;

    pub fn init(io: std.Io) @This() {
        // Zig 0.16 threads an `Io` through file operations (the std I/O refactor).
        std.Io.Dir.cwd().createDirPath(io, "logs") catch |err| {
            if (err != error.PathAlreadyExists) {
                std.debug.print("Failed to create logs directory: {}\n", .{err});
                return .{ .io = io, .file = null, .frameCounter = 0, .lastLogTime = 0 };
            }
        };

        const timestamp: i64 = @intCast(@divTrunc(std.Io.Clock.now(.real, io).nanoseconds, std.time.ns_per_s));
        const epochSeconds: u64 = @intCast(timestamp);
        const epochSeconds2000: u64 = epochSeconds - 946684800;

        const secondsPerDay: u64 = 86400;
        const secondsPerHour: u64 = 3600;
        const secondsPerMinute: u64 = 60;

        var days = epochSeconds2000 / secondsPerDay;
        const timeOfDay = epochSeconds2000 % secondsPerDay;

        const hours = timeOfDay / secondsPerHour;
        const minutes = (timeOfDay % secondsPerHour) / secondsPerMinute;
        const seconds = timeOfDay % secondsPerMinute;

        var year: u64 = 2000;
        while (true) {
            const daysInYear: u64 = if (isLeapYear(year)) 366 else 365;
            if (days < daysInYear) break;
            days -= daysInYear;
            year += 1;
        }

        const daysInMonths = [_]u64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var month: u64 = 1;
        for (daysInMonths) |daysInMonth| {
            var dim = daysInMonth;
            if (month == 2 and isLeapYear(year)) dim = 29;
            if (days < dim) break;
            days -= dim;
            month += 1;
        }
        const day = days + 1;

        var filename_buf: [64]u8 = undefined;
        const filename = std.fmt.bufPrint(&filename_buf, "logs/metrics_{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}.csv", .{
            year, month, day, hours, minutes, seconds,
        }) catch "logs/metrics.csv";

        const file = std.Io.Dir.cwd().createFile(io, filename, .{}) catch |err| {
            std.debug.print("Failed to create metrics file: {}\n", .{err});
            return .{ .io = io, .file = null, .frameCounter = 0, .lastLogTime = 0 };
        };

        file.writeStreamingAll(io, "timestamp_ms,fps,frame_time_ms,bee_count,flower_count,is_spike\n") catch {};
        std.debug.print("Metrics logging to: {s}\n", .{filename});

        return .{ .io = io, .file = file, .frameCounter = 0, .lastLogTime = 0 };
    }

    pub fn deinit(self: *@This()) void {
        if (self.file) |file| {
            file.close(self.io);
        }
    }

    pub fn log(self: *@This(), fps: f32, frameTimeMs: f32, beeCount: usize, flowerCount: usize) void {
        if (self.file == null) return;

        self.frameCounter += 1;

        const currentTime = rl.getTime();
        const timeSinceLastLog = currentTime - self.lastLogTime;
        const isSpike = frameTimeMs >= SPIKE_THRESHOLD_MS;

        if (timeSinceLastLog >= LOG_INTERVAL_SECONDS or isSpike) {
            const timestamp: i64 = @intCast(@divTrunc(std.Io.Clock.now(.real, self.io).nanoseconds, std.time.ns_per_ms));

            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{d},{d:.1},{d:.2},{d},{d},{}\n", .{
                timestamp, fps, frameTimeMs, beeCount, flowerCount, isSpike,
            }) catch return;

            self.file.?.writeStreamingAll(self.io, line) catch {};
            self.lastLogTime = currentTime;
        }
    }
};
