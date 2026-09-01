const std = @import("std");

/// Short-scale suffixes, one per 10^3. Runs past `Ud` (10^36): the last
/// tier just keeps growing (`340.28Ud` is the f32 ceiling), so a long run
/// never runs out of labels.
const SUFFIXES = [_][]const u8{ "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd" };

pub fn formatShort(value: f32, buf: []u8) [:0]const u8 {
    // A run that overflowed the f32 economy shows "inf" rather than a
    // meaningless "infDd"; NaN would otherwise print as "nan".
    if (!std.math.isFinite(value)) return if (std.math.isNan(value)) "?" else if (value < 0) "-inf" else "inf";
    const abs = @abs(value);
    if (abs < 1000.0) {
        return std.fmt.bufPrintZ(buf, "{d:.0}", .{value}) catch return "?";
    }

    var scaled = abs;
    var tier: usize = 0;
    while (scaled >= 1000.0 and tier + 1 < SUFFIXES.len) : (tier += 1) {
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
