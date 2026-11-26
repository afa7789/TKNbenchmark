//! `app wordfreq`: word frequencies. See the "wordfreq" section of SPEC.md.
//!
//! Streams standard input through a `Counter` and prints the 10 most frequent
//! words as `<count> <word>` lines.

const std = @import("std");

const Counter = @import("Counter.zig");

/// Number of words reported.
const report_len = 10;

/// Runs the subcommand: reads standard input and writes standard output.
pub fn run(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: Counter = .init(gpa);
    defer counter.deinit(gpa);

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    const in = &stdin.interface;
    while (true) {
        const chunk = in.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin.err.?,
        };
        try counter.feed(gpa, chunk);
        in.tossBuffered();
    }
    try counter.finish(gpa);

    var top_buf: [report_len]Counter.Entry = undefined;
    const top = counter.top(&top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    const out = &stdout.interface;
    for (top) |entry| {
        out.print("{d} {s}\n", .{ entry.count, entry.word }) catch return stdout.err.?;
    }
    out.flush() catch return stdout.err.?;
}

test {
    std.testing.refAllDecls(@This());
    _ = Counter;
}
