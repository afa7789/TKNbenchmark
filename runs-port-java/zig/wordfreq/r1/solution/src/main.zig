//! wordfreq: reads standard input and prints the ten most frequent ASCII words
//! as `<count> <word>` lines, by count descending, then word ascending.

const std = @import("std");
const WordCounter = @import("WordCounter.zig");

const top_n = 10;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var counter: WordCounter = .init(init.gpa);
    defer counter.deinit();

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &.{});
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try stdin_reader.interface.readSliceShort(&chunk);
        if (n == 0) break;
        try counter.feed(chunk[0..n]);
    }
    try counter.finish();

    var entries: [top_n]WordCounter.Entry = undefined;
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;
    for (counter.top(&entries)) |e| {
        try out.print("{d} {s}\n", .{ e.count, e.word });
    }
    try out.flush();
}

test {
    _ = WordCounter;
}
