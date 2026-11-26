//! Command-line entry point: evaluates one expression per line of standard
//! input and prints its value, or `error`.

const std = @import("std");
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader: std.Io.File.Reader = .initStreaming(.stdin(), io, &in_buffer);
    const in = &stdin_reader.interface;

    var out_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
    const out = &stdout_writer.interface;

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    // Holds a line that does not fit in the reader buffer.
    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    while (true) {
        line.clearRetainingCapacity();
        _ = try in.streamDelimiterEnding(&line.writer, '\n');
        try emit(&evaluator, line.written(), out);
        // The reader is left either empty at end of stream or holding the delimiter.
        if (in.bufferedLen() == 0) break;
        in.toss(1);
    }

    try out.flush();
}

fn emit(evaluator: *Evaluator, line: []const u8, out: *std.Io.Writer) !void {
    if (Evaluator.isBlank(line)) return;
    if (evaluator.evaluate(line)) |value| {
        try out.print("{d}\n", .{value});
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        error.SyntaxError, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
    }
}

test {
    _ = Evaluator;
}
