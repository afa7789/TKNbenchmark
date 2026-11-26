//! Reads one expression per line from standard input and prints its value or `error`.

const std = @import("std");
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buffer);
    var out_buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buffer);

    try run(gpa, &stdin.interface, &stdout.interface);
    try stdout.interface.flush();
}

fn run(gpa: std.mem.Allocator, in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();
    var evaluator: Evaluator = .{};
    defer evaluator.deinit(gpa);

    while (true) {
        line.clearRetainingCapacity();
        _ = try in.streamDelimiterEnding(&line.writer, '\n');
        const at_end = if (in.takeByte()) |_| false else |err| switch (err) {
            error.EndOfStream => true,
            error.ReadFailed => return err,
        };
        const text = line.written();
        if (at_end and text.len == 0) return;

        if (!isBlankLine(text)) {
            if (evaluator.evaluate(gpa, text)) |value| {
                try out.print("{d}\n", .{value});
            } else |err| switch (err) {
                error.OutOfMemory => return err,
                error.SyntaxError, error.DivisionByZero, error.Overflow => try out.writeAll("error\n"),
            }
        }
        if (at_end) return;
    }
}

fn isBlankLine(text: []const u8) bool {
    for (text) |c| {
        if (!Evaluator.isBlank(c)) return false;
    }
    return true;
}

test "run processes every line" {
    const gpa = std.testing.allocator;
    var in: std.Io.Reader = .fixed("1 + 2 * 3\n-7 / 2\n\n \t\n(1 + 2\n9223372036854775807 + 1\n5 % 0\n2*-3");
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, &in, &out.writer);
    try std.testing.expectEqualStrings("7\n-3\nerror\nerror\nerror\n-6\n", out.written());
}

test {
    _ = Evaluator;
}
