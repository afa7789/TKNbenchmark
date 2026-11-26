const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = buildSqlite(b, target, optimize);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite3", .module = sqlite.module },
        },
    });
    exe_module.linkLibrary(sqlite.library);

    const exe = b.addExecutable(.{
        .name = "notes",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the server: zig build run -- <port>");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = exe_module });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const Sqlite = struct {
    library: *std.Build.Step.Compile,
    /// Zig bindings translated from `sqlite3.h`.
    module: *std.Build.Module,
};

/// Compiles the SQLite amalgamation fetched through `build.zig.zon` into a
/// static library, so the binary does not depend on the system's SQLite.
fn buildSqlite(
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
            "-DSQLITE_DQS=0",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
            "-DSQLITE_DEFAULT_FOREIGN_KEYS=1",
            "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS",
            "-DSQLITE_OMIT_DEPRECATED",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_USE_ALLOCA",
        },
    });

    const library = b.addLibrary(.{
        .name = "sqlite3",
        .linkage = .static,
        .root_module = module,
    });

    const translate = b.addTranslateC(.{
        .root_source_file = upstream.path("sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });

    return .{ .library = library, .module = translate.createModule() };
}
