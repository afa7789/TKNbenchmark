//! wordfreq: print the 10 most frequent ASCII-letter words read from stdin.
const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ranking order: count descending, then word ascending (byte order).
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

const Counts = std.StringHashMapUnmanaged(u64);

/// Lowercases `text` in place and counts each word. Keys are slices into
/// `text`, so the buffer must outlive the returned map.
fn countWords(gpa: Allocator, text: []u8) Allocator.Error!Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);
    try counts.ensureTotalCapacity(gpa, 1 << 12);

    var i: usize = 0;
    while (i < text.len) {
        while (i < text.len and !std.ascii.isAlphabetic(text[i])) i += 1;
        const start = i;
        while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {
            text[i] = std.ascii.toLower(text[i]);
        }
        if (i > start) {
            const gop = try counts.getOrPut(gpa, text[start..i]);
            if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
        }
    }
    return counts;
}

/// Selects the highest-ranked entries into `out`, sorted by rank.
/// Returns the filled prefix of `out`.
fn selectTop(counts: *const Counts, out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len and !entry.ranksBefore(out[len - 1])) continue;
        // Insertion into the small sorted buffer, dropping the last if full.
        var pos = if (len < out.len) len else len - 1;
        while (pos > 0 and entry.ranksBefore(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = entry;
        if (len < out.len) len += 1;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const text = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Entry = undefined;
    const top = selectTop(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    try out.flush();
}

test "counts and ranks words" {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, "The cat and the hat. don't");
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var buf: [top_n]Entry = undefined;
    const top = selectTop(&counts, &buf);
    const want = [_]Entry{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "don", .count = 1 },
        .{ .word = "hat", .count = 1 },
        .{ .word = "t", .count = 1 },
    };
    try std.testing.expectEqual(want.len, top.len);
    for (want, top) |w, got| {
        try std.testing.expectEqualStrings(w.word, got.word);
        try std.testing.expectEqual(w.count, got.count);
    }
}

test "keeps only the top entries" {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, "a b c b c c");
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var buf: [2]Entry = undefined;
    const top = selectTop(&counts, &buf);
    try std.testing.expectEqual(2, top.len);
    try std.testing.expectEqualStrings("c", top[0].word);
    try std.testing.expectEqualStrings("b", top[1].word);
}
