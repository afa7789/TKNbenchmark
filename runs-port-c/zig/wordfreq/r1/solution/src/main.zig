//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words
//! (case-folded), ordered by count descending, then word ascending.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const top_n = 10;

/// Word -> occurrence count. Keys are slices into the (lowercased) input buffer.
const Counts = std.StringHashMapUnmanaged(u64);

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` should be ranked before `b`.
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

inline fn isAlpha(c: u8) bool {
    return (c | 0x20) -% 'a' < 26;
}

/// Lowercases every word in `text` in place and tallies it in `counts`.
fn countWords(gpa: Allocator, counts: *Counts, text: []u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        if (!isAlpha(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and isAlpha(text[i])) : (i += 1) {
            text[i] |= 0x20;
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
    }
}

/// Fills `top` with the best-ranked entries in order; returns how many were filled.
fn selectTop(counts: *const Counts, top: *[top_n]Entry) usize {
    var n: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (n == top_n and !e.ranksBefore(top[n - 1])) continue;
        var j: usize = if (n < top_n) blk: {
            n += 1;
            break :blk n - 1;
        } else top_n - 1;
        while (j > 0 and e.ranksBefore(top[j - 1])) : (j -= 1) {
            top[j] = top[j - 1];
        }
        top[j] = e;
    }
    return n;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buf);
    const text = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try counts.ensureTotalCapacity(gpa, 1 << 12);
    try countWords(gpa, &counts, text);

    var top: [top_n]Entry = undefined;
    const n = selectTop(&counts, &top);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top[0..n]) |e| {
        try out.print("{d} {s}\n", .{ e.count, e.word });
    }
    try out.flush();
}

test "ranking and counting" {
    const gpa = std.testing.allocator;
    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    var text = "don't stop_me 4now, now-NOW".*;
    try countWords(gpa, &counts, &text);

    var top: [top_n]Entry = undefined;
    const n = selectTop(&counts, &top);
    try std.testing.expectEqual(5, n);
    try std.testing.expectEqualStrings("now", top[0].word);
    try std.testing.expectEqual(3, top[0].count);
    try std.testing.expectEqualStrings("don", top[1].word);
    try std.testing.expectEqualStrings("t", top[4].word);
}
