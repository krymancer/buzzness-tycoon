const std = @import("std");
const rl = @import("raylib");

fn isLeapYear(year: u64) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

pub const Metrics = struct {
    file: ?std.fs.File,
    frameCounter: u32,
    lastLogTime: f64,

    const LOG_INTERVAL_SECONDS: f64 = 1.0;
    const SPIKE_THRESHOLD_MS: f32 = 33.0; // At or below 30 FPS

    pub fn init() @This() {
        // Create logs directory if it doesn't exist
        std.fs.cwd().makeDir("logs") catch |err| {
            if (err != error.PathAlreadyExists) {
                std.debug.print("Failed to create logs directory: {}\n", .{err});
                return .{
                    .file = null,
                    .frameCounter = 0,
                    .lastLogTime = 0,
                };
            }
        };

        // Generate timestamped filename
        const timestamp = std.time.timestamp();
        const epochSeconds: u64 = @intCast(timestamp);
        const epochSeconds2000: u64 = epochSeconds - 946684800; // Seconds since 2000-01-01

        // Simple date/time calculation
        const secondsPerDay: u64 = 86400;
        const secondsPerHour: u64 = 3600;
        const secondsPerMinute: u64 = 60;

        var days = epochSeconds2000 / secondsPerDay;
        const timeOfDay = epochSeconds2000 % secondsPerDay;

        const hours = timeOfDay / secondsPerHour;
        const minutes = (timeOfDay % secondsPerHour) / secondsPerMinute;
        const seconds = timeOfDay % secondsPerMinute;

        // Calculate year, month, day
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
            year,
            month,
            day,
            hours,
            minutes,
            seconds,
        }) catch "logs/metrics.csv";

        const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
            std.debug.print("Failed to create metrics file: {}\n", .{err});
            return .{
                .file = null,
                .frameCounter = 0,
                .lastLogTime = 0,
            };
        };

        // Write CSV header
        const header = "timestamp_ms,fps,frame_time_ms,bee_count,flower_count,is_spike\n";
        _ = file.write(header) catch {};

        std.debug.print("Metrics logging to: {s}\n", .{filename});

        return .{
            .file = file,
            .frameCounter = 0,
            .lastLogTime = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.file) |file| {
            file.close();
        }
    }

    pub fn log(self: *@This(), fps: f32, frameTimeMs: f32, beeCount: usize, flowerCount: usize) void {
        if (self.file == null) return;

        self.frameCounter += 1;

        const currentTime = rl.getTime();
        const timeSinceLastLog = currentTime - self.lastLogTime;
        const isSpike = frameTimeMs >= SPIKE_THRESHOLD_MS;

        // Log if interval elapsed OR if we detected a spike
        if (timeSinceLastLog >= LOG_INTERVAL_SECONDS or isSpike) {
            const timestamp = std.time.milliTimestamp();

            var buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "{d},{d:.1},{d:.2},{d},{d},{}\n", .{
                timestamp,
                fps,
                frameTimeMs,
                beeCount,
                flowerCount,
                isSpike,
            }) catch return;

            _ = self.file.?.write(line) catch {};

            // Always update lastLogTime after logging to prevent excessive logging after spikes
            self.lastLogTime = currentTime;
        }
    }
};
