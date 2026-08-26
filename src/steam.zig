//! Steamworks achievements/stats, bound at *runtime* through the flat C API.
//!
//! The SDK is never linked: on startup we try to dlopen the redistributable
//! `libsteam_api.so` / `steam_api64.dll` / `libsteam_api.dylib` sitting next
//! to the executable (the depot ships it; dev builds drop it in the repo
//! root). If the library is missing, Steam isn't running, or the app isn't
//! owned, every call here is a silent no-op and the game plays exactly as
//! before — achievements still unlock locally (save file + toast).
//!
//! Dev hooks: `BT_STEAM=0` skips the whole thing. Outside of Steam a
//! `steam_appid.txt` containing the App ID must sit in the working directory
//! for SteamAPI_Init to succeed (see `just steam-dev`).

const std = @import("std");
const builtin = @import("builtin");
const achievements = @import("achievements.zig");

pub const APP_ID: u32 = 4980570;

const is_windows = builtin.os.tag == .windows;

// Flat-API signatures (steam_api_flat.h). Every function is plain cdecl.
const InitFlatFn = *const fn (*[1024]u8) callconv(.c) c_int;
const InitFn = *const fn () callconv(.c) bool;
const VoidFn = *const fn () callconv(.c) void;
const AccessorFn = *const fn () callconv(.c) ?*anyopaque;
const NameFn = *const fn (?*anyopaque, [*:0]const u8) callconv(.c) bool;
const SetIntFn = *const fn (?*anyopaque, [*:0]const u8, i32) callconv(.c) bool;
const SetFloatFn = *const fn (?*anyopaque, [*:0]const u8, f32) callconv(.c) bool;
const SelfFn = *const fn (?*anyopaque) callconv(.c) bool;
const ResetFn = *const fn (?*anyopaque, bool) callconv(.c) bool;

/// Minimal cross-platform dynamic library handle. std.DynLib has no Windows
/// backend in Zig 0.16, so that path goes straight to kernel32.
const Lib = struct {
    const win = struct {
        extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
        extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
        extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) c_int;
    };

    handle: if (is_windows) *anyopaque else std.DynLib,

    fn open(path: [:0]const u8) ?Lib {
        if (is_windows) {
            return .{ .handle = win.LoadLibraryA(path.ptr) orelse return null };
        }
        return .{ .handle = std.DynLib.openZ(path.ptr) catch return null };
    }

    fn lookup(self: *Lib, comptime T: type, sym: [:0]const u8) ?T {
        if (is_windows) {
            const p = win.GetProcAddress(self.handle, sym.ptr) orelse return null;
            return @ptrCast(@alignCast(p));
        }
        return self.handle.lookup(T, sym);
    }

    fn close(self: *Lib) void {
        if (is_windows) {
            _ = win.FreeLibrary(self.handle);
        } else {
            self.handle.close();
        }
    }
};

const LIB_NAMES: []const [:0]const u8 = switch (builtin.os.tag) {
    .windows => &.{"steam_api64.dll"},
    .macos => &.{ "./libsteam_api.dylib", "libsteam_api.dylib" },
    else => &.{ "./libsteam_api.so", "libsteam_api.so" },
};

var lib: ?Lib = null;
var connected = false;
var userStats: ?*anyopaque = null;

var fnShutdown: ?VoidFn = null;
var fnRunCallbacks: ?VoidFn = null;
var fnSetAchievement: ?NameFn = null;
var fnClearAchievement: ?NameFn = null;
var fnSetStatInt: ?SetIntFn = null;
var fnSetStatFloat: ?SetFloatFn = null;
var fnStoreStats: ?SelfFn = null;
var fnResetAllStats: ?ResetFn = null;

/// Stats as last pushed, so a quiet colony doesn't spam StoreStats.
var lastPushed: ?achievements.Stats = null;

pub fn isConnected() bool {
    return connected;
}

pub fn init(env: *std.process.Environ.Map) void {
    if (env.get("BT_STEAM")) |v| {
        if (std.mem.eql(u8, v, "0")) {
            std.debug.print("[steam] disabled by BT_STEAM=0\n", .{});
            return;
        }
    }

    for (LIB_NAMES) |name| {
        if (Lib.open(name)) |l| {
            lib = l;
            break;
        }
    }
    var l = &(lib orelse {
        std.debug.print("[steam] no steam_api library next to the game; achievements stay local\n", .{});
        return;
    });

    // SDK 1.58+ exports SteamAPI_InitFlat (SteamAPI_Init became an inline
    // wrapper); older redistributables still export SteamAPI_Init.
    var ok = false;
    if (l.lookup(InitFlatFn, "SteamAPI_InitFlat")) |initFlat| {
        var msg: [1024]u8 = @splat(0);
        const result = initFlat(&msg);
        ok = result == 0;
        if (!ok) std.debug.print("[steam] SteamAPI_InitFlat failed ({d}): {s}\n", .{ result, std.mem.sliceTo(&msg, 0) });
    } else if (l.lookup(InitFn, "SteamAPI_Init")) |initFn| {
        ok = initFn();
        if (!ok) std.debug.print("[steam] SteamAPI_Init failed (is Steam running? steam_appid.txt present?)\n", .{});
    } else {
        std.debug.print("[steam] library has no SteamAPI_Init export\n", .{});
    }
    if (!ok) {
        l.close();
        lib = null;
        return;
    }
    fnShutdown = l.lookup(VoidFn, "SteamAPI_Shutdown");
    fnRunCallbacks = l.lookup(VoidFn, "SteamAPI_RunCallbacks");

    // Interface accessor: the version suffix tracks the SDK that built the
    // redistributable; try the ones we know, newest first.
    for ([_][:0]const u8{ "SteamAPI_SteamUserStats_v013", "SteamAPI_SteamUserStats_v012", "SteamAPI_SteamUserStats_v011" }) |sym| {
        if (l.lookup(AccessorFn, sym)) |accessor| {
            userStats = accessor();
            if (userStats != null) break;
        }
    }
    if (userStats == null) {
        std.debug.print("[steam] no ISteamUserStats accessor found; achievements stay local\n", .{});
        shutdownLib();
        return;
    }

    fnSetAchievement = l.lookup(NameFn, "SteamAPI_ISteamUserStats_SetAchievement");
    fnClearAchievement = l.lookup(NameFn, "SteamAPI_ISteamUserStats_ClearAchievement");
    fnSetStatInt = l.lookup(SetIntFn, "SteamAPI_ISteamUserStats_SetStatInt32");
    fnSetStatFloat = l.lookup(SetFloatFn, "SteamAPI_ISteamUserStats_SetStatFloat");
    fnStoreStats = l.lookup(SelfFn, "SteamAPI_ISteamUserStats_StoreStats");
    fnResetAllStats = l.lookup(ResetFn, "SteamAPI_ISteamUserStats_ResetAllStats");
    if (fnSetAchievement == null or fnStoreStats == null) {
        std.debug.print("[steam] ISteamUserStats exports missing; achievements stay local\n", .{});
        shutdownLib();
        return;
    }
    // Pre-1.61 SDKs need an explicit stats fetch before writes are accepted;
    // newer ones load them at init and dropped the call.
    if (l.lookup(SelfFn, "SteamAPI_ISteamUserStats_RequestCurrentStats")) |request| _ = request(userStats);

    connected = true;
    std.debug.print("[steam] connected (app {d})\n", .{APP_ID});
}

fn shutdownLib() void {
    if (fnShutdown) |shutdown| shutdown();
    if (lib) |*l| l.close();
    lib = null;
    connected = false;
    userStats = null;
    fnShutdown = null;
    fnRunCallbacks = null;
}

pub fn deinit() void {
    if (lib == null) return;
    shutdownLib();
}

/// Pump Steam callbacks; call once per frame.
pub fn runCallbacks() void {
    if (!connected) return;
    if (fnRunCallbacks) |run| run();
}

/// Unlock on Steam and commit right away (StoreStats pops the overlay toast).
pub fn unlockAchievement(api: [:0]const u8) void {
    if (!connected) return;
    _ = fnSetAchievement.?(userStats, api.ptr);
    _ = fnStoreStats.?(userStats);
}

/// Mirror the lifetime counters as Steam stats (progress bars on the
/// achievement page). Skips the round trip when nothing changed.
pub fn pushStats(stats: *const achievements.Stats) void {
    if (!connected) return;
    if (lastPushed) |prev| {
        if (std.meta.eql(prev, stats.*)) return;
    }
    inline for (@typeInfo(achievements.Stat).@"enum".fields) |f| {
        const stat: achievements.Stat = @enumFromInt(f.value);
        const value = stats.get(stat);
        switch (stat.kind()) {
            .int => if (fnSetStatInt) |set| {
                const clamped: i32 = @intFromFloat(@min(value, @as(f64, std.math.maxInt(i32))));
                _ = set(userStats, stat.api().ptr, clamped);
            },
            .float => if (fnSetStatFloat) |set| {
                const clamped: f32 = @floatCast(@min(value, @as(f64, std.math.floatMax(f32))));
                _ = set(userStats, stat.api().ptr, clamped);
            },
        }
    }
    _ = fnStoreStats.?(userStats);
    lastPushed = stats.*;
}

/// Dev hook: wipe this account's achievements *and* stats for the app so a
/// run can be re-tested from scratch (BT_RESET_ACHIEVEMENTS=1).
pub fn resetAll() void {
    if (!connected) return;
    if (fnResetAllStats) |reset| _ = reset(userStats, true);
    _ = fnStoreStats.?(userStats);
    lastPushed = null;
    std.debug.print("[steam] achievements and stats reset\n", .{});
}
