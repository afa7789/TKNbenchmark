//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! Words are folded to lowercase and ranked by count descending, then by word
//! ascending (byte order). Output is one `<count> <word>` line per word.

const std = @import("std");
const WordCounter = @import("WordCounter.zig");

const top_n = 10;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var counter: WordCounter = .init(init.gpa);
    defer counter.deinit();

    var in_buffer: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    while (true) {
        const chunk = stdin.interface.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin.err.?,
        };
        try counter.feed(chunk);
        stdin.interface.tossBuffered();
    }
    try counter.finish();

    var top_buffer: [top_n]WordCounter.Entry = undefined;
    const top = counter.top(&top_buffer);

    var out_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    writeTop(&stdout.interface, top) catch |err| switch (err) {
        // A reader that stops early (e.g. `| head -1`) is not an error.
        error.WriteFailed => switch (stdout.err.?) {
            error.BrokenPipe => {},
            else => |e| return e,
        },
    };
}

fn writeTop(out: *std.Io.Writer, top: []const WordCounter.Entry) std.Io.Writer.Error!void {
    for (top) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    try out.flush();
}

test {
    _ = WordCounter;
}
