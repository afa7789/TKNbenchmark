const std = @import("std");

/// Every subcommand lives in `src/<name>/root.zig` and is exposed to the
/// dispatcher as a module of the same name. Adding files inside a subcommand's
/// directory never requires touching this file.
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

        const mod_tests = b.addTest(.{ .name = name, .root_module = mod });
        const run_mod_tests = b.addRunArtifact(mod_tests);
        test_step.dependOn(&run_mod_tests.step);

        const sub_test_step = b.step(
            b.fmt("test-{s}", .{name}),
            b.fmt("Run unit tests for the {s} subcommand", .{name}),
        );
        sub_test_step.dependOn(&run_mod_tests.step);
    }

    const exe = b.addExecutable(.{ .name = "app", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{ .name = "app", .root_module = exe_mod });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
