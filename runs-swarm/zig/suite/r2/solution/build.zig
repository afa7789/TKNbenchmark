const std = @import("std");

/// Each subcommand is an independent module rooted at `src/<name>/<name>.zig`
/// and exposes `pub fn run(gpa, in, out) !void`. The names here must match the
/// subcommand names dispatched in `src/main.zig`.
const subcommands = [_][]const u8{ "wordfreq", "lru", "calc" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");

    for (subcommands) |name| {
        const mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}/{s}.zig", .{ name, name })),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport(name, mod);

        const mod_tests = b.addTest(.{ .name = name, .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    }

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const exe_tests = b.addTest(.{ .name = "main", .root_module = exe_mod });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
