//! calc: evaluates one 64-bit signed integer expression per input line.
//!
//! Each non-blank line of standard input is evaluated and its value (or
//! `error`) is written to standard output. See SPEC.md for the grammar.

const std = @import("std");
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    const in = &stdin.interface;

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    const out = &stdout.interface;

    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();

    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (try readLine(in, &line)) |text| {
        if (isBlank(text)) continue;
        if (evaluator.evaluate(text)) |value| {
            try out.print("{d}\n", .{value});
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Syntax, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
        }
    }
    try out.flush();
}

/// Reads the next line (without its trailing '\n') into `line`, which is
/// reused between calls. Lines of any length are supported. Returns null at
/// end of input; a final line lacking '\n' is still returned.
fn readLine(in: *std.Io.Reader, line: *std.Io.Writer.Allocating) !?[]const u8 {
    line.clearRetainingCapacity();
    _ = in.streamDelimiterEnding(&line.writer, '\n') catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
        error.ReadFailed => return error.ReadFailed,
    };
    const found_newline = if (in.takeByte()) |_| true else |err| switch (err) {
        error.EndOfStream => false,
        error.ReadFailed => return error.ReadFailed,
    };
    const text = line.written();
    if (!found_newline and text.len == 0) return null;
    return text;
}

fn isBlank(text: []const u8) bool {
    return std.mem.indexOfNone(u8, text, " \t") == null;
}

test {
    _ = Evaluator;
}

test isBlank {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank(" 1 "));
}

test readLine {
    var reader: std.Io.Reader = .fixed("a\n\nbc");
    var line: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer line.deinit();
    try std.testing.expectEqualStrings("a", (try readLine(&reader, &line)).?);
    try std.testing.expectEqualStrings("", (try readLine(&reader, &line)).?);
    try std.testing.expectEqualStrings("bc", (try readLine(&reader, &line)).?);
    try std.testing.expectEqual(null, try readLine(&reader, &line));
}
