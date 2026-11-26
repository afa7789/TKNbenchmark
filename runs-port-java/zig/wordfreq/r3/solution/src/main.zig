//! wordfreq: prints the ten most frequent ASCII words read from standard input.

const std = @import("std");
const WordCounter = @import("WordCounter.zig");

const top_n = 10;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var read_buffer: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &read_buffer);
    const text = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counter: WordCounter = .{};
    defer counter.deinit(gpa);
    try counter.addText(gpa, text);

    var best: [top_n]WordCounter.WordCount = undefined;

    var write_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &write_buffer);
    const out = &stdout.interface;
    for (counter.top(&best)) |wc| {
        try out.print("{d} {s}\n", .{ wc.count, wc.word });
    }
    try out.flush();
}

test {
    _ = WordCounter;
}
