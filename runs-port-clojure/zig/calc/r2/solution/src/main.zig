//! calc: reads one integer expression per line from stdin and prints its
//! value, or `error`, for every non-blank line.

const std = @import("std");
const calc = @import("calc.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);

    var evaluator = calc.Evaluator.init(init.gpa);
    defer evaluator.deinit();

    try run(&stdin.interface, &stdout.interface, &evaluator);
    try stdout.interface.flush();
}

/// Evaluates every line of `in`, writing results to `out`. Lines end with
/// `\n`; a `\r` or `\r\n` terminator is accepted as well, and a final line
/// without a terminator is still evaluated.
fn run(in: *std.Io.Reader, out: *std.Io.Writer, evaluator: *calc.Evaluator) !void {
    // Set when a chunk ended in `\r`, so a `\n` opening the next is skipped.
    var after_cr = false;
    while (true) {
        var rest = in.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return error.ReadFailed,
        };
        in.tossBuffered();

        if (after_cr and rest[0] == '\n') rest = rest[1..];
        after_cr = false;

        while (std.mem.indexOfAny(u8, rest, "\r\n")) |end| {
            try evaluator.feed(rest[0..end]);
            try emit(out, try evaluator.finish());
            var next = end + 1;
            if (rest[end] == '\r') {
                if (next == rest.len) {
                    after_cr = true;
                } else if (rest[next] == '\n') {
                    next += 1;
                }
            }
            rest = rest[next..];
        }
        try evaluator.feed(rest);
    }
    try emit(out, try evaluator.finish());
}

fn emit(out: *std.Io.Writer, outcome: calc.Outcome) std.Io.Writer.Error!void {
    switch (outcome) {
        .blank => {},
        .value => |v| try out.print("{d}\n", .{v}),
        .failure => try out.writeAll("error\n"),
    }
}

test {
    _ = calc;
}
