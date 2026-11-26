//! `app calc`: 64-bit integer expression evaluator. See the "calc" section of SPEC.md.
//!
//! Reads expressions line by line from standard input and prints each value,
//! or `error`, on its own line. Blank lines print nothing.

const std = @import("std");
const Io = std.Io;

pub const Evaluator = @import("Evaluator.zig");

/// Runs the subcommand: reads standard input and writes standard output.
pub fn run(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &in_buffer);
    var out_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &out_buffer);

    evaluateLines(gpa, &stdin_reader.interface, &stdout_writer.interface) catch |err| switch (err) {
        error.ReadFailed => return stdin_reader.err.?,
        error.WriteFailed => return stdout_writer.err.?,
        error.OutOfMemory => return error.OutOfMemory,
    };
    stdout_writer.interface.flush() catch return stdout_writer.err.?;
}

/// Evaluates every line of `in` and writes the results to `out`. Lines may be
/// of any length; a final line without a terminating `\n` is still evaluated.
pub fn evaluateLines(
    gpa: std.mem.Allocator,
    in: *Io.Reader,
    out: *Io.Writer,
) error{ ReadFailed, WriteFailed, OutOfMemory }!void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();
    var line: Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    while (true) {
        line.clearRetainingCapacity();
        _ = in.streamDelimiterEnding(&line.writer, '\n') catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            error.ReadFailed => return error.ReadFailed,
        };
        // Unless the stream has ended, the reader is positioned at the delimiter.
        const terminated = if (in.takeByte()) |_| true else |err| switch (err) {
            error.EndOfStream => false,
            error.ReadFailed => return error.ReadFailed,
        };

        const expr = line.written();
        if (!Evaluator.isBlank(expr)) {
            if (evaluator.eval(expr)) |value| {
                try out.print("{d}\n", .{value});
            } else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.SyntaxError, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
            }
        }

        if (!terminated) return;
    }
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try evaluateLines(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput(
        "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n",
        "7\n-3\nerror\nerror\n",
    );
}

test "blank lines and missing final newline" {
    try expectOutput("\n  42  \n\t\n1+1", "42\n2\n");
    try expectOutput("", "");
}

test {
    std.testing.refAllDecls(@This());
}
