const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = sqliteModule(b, target, optimize);

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlite_c", .module = sqlite.c_module },
        },
    });
    app_mod.linkLibrary(sqlite.lib);

    const exe = b.addExecutable(.{
        .name = "notes",
        .root_module = app_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the notes server (pass the port after `--`)");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{ .root_module = app_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const Sqlite = struct {
    lib: *std.Build.Step.Compile,
    c_module: *std.Build.Module,
};

/// Builds the SQLite amalgamation (fetched through build.zig.zon) as a static
/// library and exposes its header as a translated-C module.
fn sqliteModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) Sqlite {
    const upstream = b.dependency("sqlite", .{});

    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addCSourceFile(.{
        .file = upstream.path("sqlite3.c"),
        .flags = &.{
            // Recommended compile-time options, see https://sqlite.org/compile.html
            "-DSQLITE_DQS=0",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_DEFAULT_MEMSTATUS=0",
            "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
            "-DSQLITE_DEFAULT_FOREIGN_KEYS=1",
            "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS",
            "-DSQLITE_MAX_EXPR_DEPTH=0",
            "-DSQLITE_OMIT_DEPRECATED",
            "-DSQLITE_OMIT_LOAD_EXTENSION",
            "-DSQLITE_OMIT_SHARED_CACHE",
            "-DSQLITE_USE_ALLOCA",
            "-DSQLITE_ENABLE_API_ARMOR",
        },
    });
    const lib = b.addLibrary(.{
        .name = "sqlite3",
        .root_module = lib_mod,
    });

    const translate = b.addTranslateC(.{
        .root_source_file = upstream.path("sqlite3.h"),
        .target = target,
        .optimize = optimize,
    });

    return .{ .lib = lib, .c_module = translate.createModule() };
}
