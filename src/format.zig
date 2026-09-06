const std = @import("std");

/// Short-scale suffixes, one per 10^3. Runs past `Ud` (10^36): the last
/// tier just keeps growing (`340.28Ud` is the f32 ceiling), so a long run
/// never runs out of labels.
const SUFFIXES = [_][]const u8{ "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd" };

// f64 so values that outgrow the f32 economy (run-honey totals) still print;
// f32 callers coerce.
pub fn formatShort(value: f64, buf: []u8) [:0]const u8 {
    // A run that overflowed the economy shows "inf" rather than a
    // meaningless "infDd"; NaN would otherwise print as "nan".
    if (!std.math.isFinite(value)) return if (std.math.isNan(value)) "?" else if (value < 0) "-inf" else "inf";
    const abs = @abs(value);
    if (abs < 1000.0) {
        return std.fmt.bufPrintZ(buf, "{d:.0}", .{value}) catch return "?";
    }

    var scaled = abs;
    var tier: usize = 0;
    // 999.995 is where {d:.2} rounds to "1000.00": promoting there keeps a
    // value that repeated division left one ULP under 1000 (e.g. 1e33) from
    // printing as "1000.00No" instead of "1.00Dc".
    while (scaled >= 999.995 and tier + 1 < SUFFIXES.len) : (tier += 1) {
        scaled /= 1000.0;
    }

    const signed = if (value < 0) -scaled else scaled;
    return std.fmt.bufPrintZ(buf, "{d:.2}{s}", .{ signed, SUFFIXES[tier] }) catch return "?";
}

test "formatShort tiers" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0", formatShort(0, &buf));
    try std.testing.expectEqualStrings("999", formatShort(999, &buf));
    try std.testing.expectEqualStrings("1.00K", formatShort(1000, &buf));
    try std.testing.expectEqualStrings("1.50K", formatShort(1500, &buf));
    try std.testing.expectEqualStrings("2.35M", formatShort(2_350_000, &buf));
    try std.testing.expectEqualStrings("1.00B", formatShort(1_000_000_000, &buf));
}

test "formatShort covers the whole f32 range without running out of suffixes" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("764.86No", formatShort(7.6486e32, &buf));
    try std.testing.expectEqualStrings("1.00Dc", formatShort(1e33, &buf));
    try std.testing.expectEqualStrings("1.00Ud", formatShort(1e36, &buf));
    try std.testing.expectEqualStrings("340.28Ud", formatShort(std.math.floatMax(f32), &buf));
    try std.testing.expectEqualStrings("inf", formatShort(std.math.inf(f32), &buf));
    try std.testing.expectEqualStrings("-inf", formatShort(-std.math.inf(f32), &buf));
    try std.testing.expectEqualStrings("?", formatShort(std.math.nan(f32), &buf));
}

/// Compact wait time for "affordable in ..." hints: "12s", "3m", "2h",
/// "5d"; anything past 99 days is just ">99d". Null when it will never
/// happen (no income) so callers can hide the hint.
pub fn formatEta(seconds: f64, buf: []u8) ?[:0]const u8 {
    if (!std.math.isFinite(seconds) or seconds < 0) return null;
    if (seconds < 60) return std.fmt.bufPrintZ(buf, "{d:.0}s", .{@ceil(seconds)}) catch null;
    if (seconds < 3600) return std.fmt.bufPrintZ(buf, "{d:.0}m", .{@ceil(seconds / 60)}) catch null;
    if (seconds < 86400) return std.fmt.bufPrintZ(buf, "{d:.0}h", .{@ceil(seconds / 3600)}) catch null;
    if (seconds < 99 * 86400) return std.fmt.bufPrintZ(buf, "{d:.0}d", .{@ceil(seconds / 86400)}) catch null;
    return ">99d";
}

/// Seconds until `cost` is reachable from `have` at `perSec`; null when
/// there's no income. Zero when it's already affordable.
pub fn secondsUntil(cost: f64, have: f64, perSec: f64) ?f64 {
    if (have >= cost) return 0;
    if (!(perSec > 0)) return null;
    return (cost - have) / perSec;
}

test "formatEta picks the coarsest readable unit" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("12s", formatEta(11.2, &buf).?);
    try std.testing.expectEqualStrings("1m", formatEta(60, &buf).?);
    try std.testing.expectEqualStrings("3m", formatEta(150, &buf).?);
    try std.testing.expectEqualStrings("2h", formatEta(7000, &buf).?);
    try std.testing.expectEqualStrings("5d", formatEta(5 * 86400 - 1, &buf).?);
    try std.testing.expectEqualStrings(">99d", formatEta(1e9, &buf).?);
    try std.testing.expect(formatEta(std.math.inf(f64), &buf) == null);
    try std.testing.expectEqual(@as(?f64, 0), secondsUntil(10, 10, 0));
    try std.testing.expectEqual(@as(?f64, null), secondsUntil(10, 5, 0));
    try std.testing.expectEqual(@as(?f64, 5), secondsUntil(10, 5, 1));
}
