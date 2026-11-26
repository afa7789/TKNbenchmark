//! calc: reads one expression per line from stdin and prints its value,
//! or `error`, for each non-blank line.

const std = @import("std");
const Io = std.Io;
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &stdin_buffer);
    const in = &stdin_reader.interface;

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;

    // Holds lines too long to fit in the reader's buffer.
    var long_line: Io.Writer.Allocating = .init(gpa);
    defer long_line.deinit();

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (try nextLine(in, &long_line)) |line| {
        const result = evaluator.evaluate(line) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.SyntaxError, error.DivisionByZero, error.Overflow => {
                try out.writeAll("error\n");
                continue;
            },
        };
        if (result) |value| try out.print("{d}\n", .{value});
    }
    try out.flush();
}

/// Returns the next line without its trailing `\n`, or `null` at end of input.
/// The slice is valid until the next call.
fn nextLine(in: *Io.Reader, long_line: *Io.Writer.Allocating) !?[]const u8 {
    if (in.takeDelimiter('\n')) |line| {
        return line;
    } else |err| switch (err) {
        error.StreamTooLong => {},
        error.ReadFailed => return err,
    }
    long_line.clearRetainingCapacity();
    _ = try in.streamDelimiterEnding(&long_line.writer, '\n');
    if (in.bufferedLen() > 0) in.toss(1); // the delimiter
    return long_line.written();
}

test {
    _ = Evaluator;
}
