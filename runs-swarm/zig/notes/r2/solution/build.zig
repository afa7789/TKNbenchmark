const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = sqliteLibrary(b, target, optimize);

    const sqlite_c = b.addTranslateC(.{
        .root_source_file = sqlite.header,
        .target = target,
        .optimize = optimize,
    });

    const app_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite_c", .module = sqlite_c.createModule() },
        },
    });
    app_module.linkLibrary(sqlite.lib);

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = app_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the server: zig build run -- <port>");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = app_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const Sqlite = struct {
    lib: *std.Build.Step.Compile,
    header: std.Build.LazyPath,
};

/// Builds the SQLite amalgamation fetched through build.zig.zon as a static library.
fn sqliteLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) Sqlite {
    const upstream = b.dependency("sqlite", .{});

    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addCSourceFile(.{
        .file = upstream.path("sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=2", // connections are never shared between threads unguarded
            "-DSQLITE_DQS=0",
            "-DSQLITE_DEFAULT_FOREIGN_KEYS=1",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
            "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS",
            "-DSQLITE_OMIT_DEPRECATED",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_USE_ALLOCA",
        },
    });
    module.addIncludePath(upstream.path("."));

    const lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = module,
        .linkage = .static,
    });

    return .{ .lib = lib, .header = upstream.path("sqlite3.h") };
}
