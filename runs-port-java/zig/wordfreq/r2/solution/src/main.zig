//! wordfreq: prints the ten most frequent ASCII-letter words read from
//! standard input as `<count> <word>` lines.

const std = @import("std");
const WordCounter = @import("WordCounter.zig");

const top_n = 10;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: WordCounter = .init(gpa);
    defer counter.deinit();

    {
        var tokenizer: WordCounter.Tokenizer = .{ .counter = &counter };
        defer tokenizer.deinit();

        var read_buffer: [64 * 1024]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(io, &read_buffer);
        const reader = &stdin_reader.interface;
        while (true) {
            const chunk = reader.peekGreedy(1) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => return stdin_reader.err.?,
            };
            try tokenizer.feed(chunk);
            reader.toss(chunk.len);
        }
        try tokenizer.flush();
    }

    const entries = try counter.top(gpa, top_n);
    defer gpa.free(entries);

    var write_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &write_buffer);
    const out = &stdout_writer.interface;
    for (entries) |entry| {
        try out.print("{d} {s}\n", .{ entry.count, entry.word });
    }
    try out.flush();
}

test {
    _ = WordCounter;
}
