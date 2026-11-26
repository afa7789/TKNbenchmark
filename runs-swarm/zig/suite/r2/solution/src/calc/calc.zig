//! `app calc` — see the "calc" section of SPEC.md.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Evaluator = @import("Evaluator.zig");

/// 64-bit signed integer expression evaluator: evaluate each line of `in`.
///
/// `in` is standard input and `out` is buffered standard output; the caller
/// flushes `out` after this returns. `gpa` is a general-purpose allocator.
pub fn run(gpa: Allocator, in: *Io.Reader, out: *Io.Writer) !void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();
    var long_line: Io.Writer.Allocating = .init(gpa);
    defer long_line.deinit();

    while (try nextLine(in, &long_line)) |line| {
        if (std.mem.trim(u8, line, " \t").len == 0) continue;
        if (evaluator.eval(line)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
}

/// Returns the next line of `in` without its '\n', or null at end of stream.
///
/// Lines that fit in the reader's buffer are returned in place; longer ones
/// are accumulated in `long_line`. The result is valid until the next call.
fn nextLine(in: *Io.Reader, long_line: *Io.Writer.Allocating) !?[]const u8 {
    if (in.takeDelimiter('\n')) |line| {
        return line;
    } else |err| switch (err) {
        error.StreamTooLong => {},
        error.ReadFailed => return error.ReadFailed,
    }

    long_line.clearRetainingCapacity();
    // The only failure of an allocating writer is running out of memory.
    _ = in.streamDelimiterEnding(&long_line.writer, '\n') catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.ReadFailed => return error.ReadFailed,
    };
    // Discard the delimiter, unless the stream ended without one.
    if (in.bufferedLen() > 0) in.toss(1);
    return long_line.written();
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&buf);
    try run(std.testing.allocator, &in, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test run {
    try expectOutput("", "");
    try expectOutput(
        "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n",
        "7\n-3\nerror\nerror\n",
    );
    try expectOutput("\n  42  \n\t\n1+1", "42\n2\n");
}

test "lines longer than the reader buffer" {
    const input = "1 + 2 + 3\n" ++ "(" ** 40 ++ "4" ++ ")" ** 40 ++ "\n5 / 0\n" ++ "-" ** 50 ++ "6";
    var backing: [16]u8 = undefined;
    var in: Io.Reader = .fixed(input);
    var limited = in.limited(.unlimited, &backing);
    var buf: [64]u8 = undefined;
    var out: Io.Writer = .fixed(&buf);
    try run(std.testing.allocator, &limited.interface, &out);
    try std.testing.expectEqualStrings("6\n4\nerror\n6\n", out.buffered());
}

test {
    _ = Evaluator;
}
