const std = @import("std");

const SUFFIXES = [_][]const u8{ "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" };

pub fn formatShort(value: f32, buf: []u8) [:0]const u8 {
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
