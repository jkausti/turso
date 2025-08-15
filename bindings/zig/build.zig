const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_turso = b.createModule(.{
        .root_source_file = b.path("src/zig-turso.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_zig_turso = b.addStaticLibrary(.{
        .name = "zig-turso",
        .root_module = zig_turso,
    });

    lib_zig_turso.linkLibC();
    lib_zig_turso.addIncludePath(b.path("header"));
    lib_zig_turso.addLibraryPath(b.path("../../target/debug"));
    lib_zig_turso.linkSystemLibrary("_limbo_zig");

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "_turso_zig",
        .root_module = exe_mod,
    });

    exe.linkLibrary(lib_zig_turso);

    exe.linkLibC();
    exe.addIncludePath(b.path("header"));
    exe.addLibraryPath(b.path("../../target/debug"));
    exe.linkSystemLibrary("_limbo_zig");

    b.installArtifact(exe);

    // tests setup

    const test_exe = b.addTest(.{
        .root_source_file = b.path("tests/lib.zig"),
        .filters = b.option(
            []const []const u8,
            "test-filter",
            "test-filter",
        ) orelse &.{},
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });

    test_exe.linkLibC();
    test_exe.addIncludePath(b.path("header"));
    test_exe.addLibraryPath(b.path("../../target/debug"));
    test_exe.linkSystemLibrary("_limbo_zig");

    // test_exe.root_module.addImport("zig-turso", zig_turso);
    // test_exe.linkLibrary(lib_zig_turso);
    test_exe.root_module.addImport("turso", zig_turso);

    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
