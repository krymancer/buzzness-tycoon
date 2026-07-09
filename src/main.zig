const std = @import("std");
const Game = @import("game.zig").Game;

// Zig 0.16 entry point: `Init` hands us a ready allocator, an Io implementation,
// and the process environment — no manual GPA/Threaded setup needed.
pub fn main(init: std.process.Init) !void {
    var game = try Game.init(init.gpa, init.io, init.environ_map);
    defer game.deinit();

    try game.run();
}
