//! calc: reads one expression per line from standard input and prints its
//! value, or `error`. Lines that are empty or hold only blanks print nothing.

const std = @import("std");
const Evaluator = @import("Evaluator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    var out_buffer: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buffer);

    try run(init.gpa, &stdin.interface, &stdout.interface);
    try stdout.interface.flush();
}

/// Evaluates every `\n`-terminated line of `in` (a final unterminated line
/// included), writing one result per non-blank line to `out`.
fn run(gpa: std.mem.Allocator, in: *std.Io.Reader, out: *std.Io.Writer) !void {
    var evaluator: Evaluator = .init(gpa);
    defer evaluator.deinit();

    while (true) {
        const chunk = in.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        var rest = chunk;
        while (std.mem.findScalar(u8, rest, '\n')) |end| {
            try evaluator.feedSlice(rest[0..end]);
            try emit(out, try evaluator.finish());
            rest = rest[end + 1 ..];
        }
        try evaluator.feedSlice(rest);
        in.toss(chunk.len);
    }
    try emit(out, try evaluator.finish());
}

fn emit(out: *std.Io.Writer, result: Evaluator.Result) std.Io.Writer.Error!void {
    switch (result) {
        .blank => {},
        .value => |value| try out.print("{d}\n", .{value}),
        .failure => try out.writeAll("error\n"),
    }
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var reader: std.Io.Reader = .fixed(input);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try run(std.testing.allocator, &reader, &output.writer);
    try std.testing.expectEqualStrings(expected, output.written());
}

test "spec example" {
    try expectOutput(
        "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n",
        "7\n-3\nerror\nerror\n",
    );
}

test "blank lines and unterminated last line" {
    try expectOutput("\n  42  \n\t\n1+1", "42\n2\n");
    try expectOutput("", "");
    try expectOutput("1\r\n", "error\n");
}

test {
    _ = Evaluator;
}
