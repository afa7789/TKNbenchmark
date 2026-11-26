const std = @import("std");

/// Subcommands of `app`. Each one is an independent module rooted at
/// `src/<name>/root.zig` that exposes `pub fn run(init: std.process.Init) !void`.
const subcommands = [_][]const u8{ "wordfreq", "lru", "calc" };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run all unit tests");

    for (subcommands) |name| {
        const mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}/root.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport(name, mod);

        const run_tests = b.addRunArtifact(b.addTest(.{ .root_module = mod }));
        const step = b.step(b.fmt("test-{s}", .{name}), b.fmt("Run unit tests of the {s} subcommand", .{name}));
        step.dependOn(&run_tests.step);
        test_step.dependOn(&run_tests.step);
    }

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app (pass the subcommand after --)");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addRunArtifact(b.addTest(.{ .root_module = exe_mod }));
    test_step.dependOn(&exe_tests.step);
}
