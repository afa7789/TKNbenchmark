//! `app calc`: see the "calc" section of SPEC.md.
//!
//! This module is owned by the calc subcommand. Additional files belong in
//! `src/calc/` and are imported from here.

const std = @import("std");
const Io = std.Io;
const Evaluator = @import("Evaluator.zig");

/// Runs the subcommand: reads standard input, writes standard output.
pub fn run(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    try evaluateLines(&evaluator, input, out);
    try out.flush();
}

/// Writes one output line per non-blank line of `input`: the value of its
/// expression, or `error`.
fn evaluateLines(evaluator: *Evaluator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t").len == 0) continue;
        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
}

test {
    _ = Evaluator;
}

test evaluateLines {
    var evaluator: Evaluator = .init(std.testing.allocator);
    defer evaluator.deinit();
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    try evaluateLines(&evaluator, "1 + 2 * 3\n-7 / 2\n\n \t\n(1 + 2\n9223372036854775807 + 1\n2", &out.writer);
    try std.testing.expectEqualStrings("7\n-3\nerror\nerror\n2\n", out.written());
}
