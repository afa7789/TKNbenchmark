//! Reads one integer expression per line from stdin and prints its value or
//! `error`. Blank lines produce no output.

const std = @import("std");
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &in_buffer);
    const in = &stdin_reader.interface;

    var out_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &out_buffer);
    const out = &stdout_writer.interface;

    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (true) {
        line.clearRetainingCapacity();
        _ = try in.streamDelimiterEnding(&line.writer, '\n');
        const at_end = if (in.takeByte()) |_| false else |err| switch (err) {
            error.EndOfStream => true,
            else => |e| return e,
        };
        if (at_end and line.written().len == 0) break;

        if (evaluator.evaluate(line.written())) |result| {
            if (result) |value| try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }

        if (at_end) break;
    }
    try out.flush();
}

test {
    _ = Evaluator;
}
