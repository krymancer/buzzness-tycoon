const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    // Add a module for the sprites
    const sprites_module = b.addModule("sprites", .{
        .root_source_file = b.path("sprites/sprite_index.zig"),
    });

    // Game version shown on the title screen. CI passes the release tag via
    // -Dversion=...; local builds fall back to `git describe` (e.g.
    // "0.2.1-3-gabc1234-dirty"), then "dev".
    const version = b.option([]const u8, "version", "Version string baked into the build (CI passes the release tag)") orelse blk: {
        var code: u8 = 0;
        const out = b.runAllowFail(&.{ "git", "describe", "--tags", "--always", "--dirty" }, &code, .ignore) catch break :blk "dev";
        const trimmed = std.mem.trim(u8, out, " \n\r\t");
        break :blk if (code == 0 and trimmed.len > 0) trimmed else "dev";
    };
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    const build_options_module = build_options.createModule();

    const exe = b.addExecutable(.{
        .name = "buzzness-tycoon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);
    exe.root_module.addImport("sprites", sprites_module);
    exe.root_module.addImport("build_options", build_options_module);

    // Add path to the sprites directory for @embedFile
    exe.root_module.addIncludePath(b.path(".")); // Makes the project root accessible

    // On Windows, use the GUI subsystem so no console window pops up behind the
    // game when launched from Steam / a desktop shortcut.
    if (target.result.os.tag == .windows) exe.subsystem = .Windows;
    // Strip debug info from release builds (smaller download, no symbols shipped).
    exe.root_module.strip = optimize != .Debug;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Check step for fast compile checking (useful for editor on-save hooks)
    const exe_check = b.addExecutable(.{
        .name = "buzzness-tycoon",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe_check.root_module.linkLibrary(raylib_artifact);
    exe_check.root_module.addImport("raylib", raylib);
    exe_check.root_module.addImport("raygui", raygui);
    exe_check.root_module.addImport("sprites", sprites_module);
    exe_check.root_module.addImport("build_options", build_options_module);

    const check_step = b.step("check", "Check if the app compiles without linking");
    check_step.dependOn(&exe_check.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // utils.zig (grid-math tests) uses raylib types.
    lib_unit_tests.root_module.linkLibrary(raylib_artifact);
    lib_unit_tests.root_module.addImport("raylib", raylib);
    lib_unit_tests.root_module.addImport("build_options", build_options_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
