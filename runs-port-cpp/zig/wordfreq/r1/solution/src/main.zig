//! wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
const std = @import("std");

const top_n = 10;

const Counts = std.StringHashMapUnmanaged(u64);

const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ranking order: count descending, then word ascending (byte order).
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

fn isAsciiLetter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

/// Lowercases every word in `text` in place and counts occurrences.
/// Keys in the returned map are slices of `text`, which must outlive it.
fn countWords(gpa: std.mem.Allocator, text: []u8) !Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < text.len) {
        if (!isAsciiLetter(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and isAsciiLetter(text[i])) : (i += 1) {
            text[i] |= 0x20; // ASCII letters only: sets the lowercase bit.
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
    }
    return counts;
}

/// Selects the `buf.len` highest-ranked entries into `buf`, sorted; returns the filled prefix.
fn topWords(counts: *const Counts, buf: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buf.len and !entry.ranksBefore(buf[len - 1])) continue;
        // Insertion into the sorted prefix, dropping the last element when full.
        var pos = if (len < buf.len) len else len - 1;
        while (pos > 0 and entry.ranksBefore(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = entry;
        if (len < buf.len) len += 1;
    }
    return buf[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var read_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &read_buf);
    const text = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &top_buf);

    var write_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &write_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| {
        try out.print("{d} {s}\n", .{ entry.count, entry.word });
    }
    try out.flush();
}

test "counts and ranks words case-insensitively" {
    const gpa = std.testing.allocator;
    var text = "The cat and the hat. don't".*;
    var counts = try countWords(gpa, &text);
    defer counts.deinit(gpa);

    var buf: [3]Entry = undefined;
    const top = topWords(&counts, &buf);
    try std.testing.expectEqual(@as(usize, 3), top.len);
    try std.testing.expectEqualStrings("the", top[0].word);
    try std.testing.expectEqual(@as(u64, 2), top[0].count);
    try std.testing.expectEqualStrings("and", top[1].word);
    try std.testing.expectEqualStrings("cat", top[2].word);
}
