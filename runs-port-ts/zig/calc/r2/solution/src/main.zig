//! Reads one expression per line from standard input and prints its value,
//! or `error`, for each non-blank line.

const std = @import("std");
const calc = @import("calc.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var evaluator: calc.Evaluator = .init(gpa);
    defer evaluator.deinit();

    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        // A trailing newline terminates the last line rather than starting a new one.
        if (lines.index == null and line.len == 0) break;
        if (calc.isBlank(line)) continue;

        if (evaluator.evaluate(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

test {
    _ = calc;
}
