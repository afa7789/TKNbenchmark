//! wordfreq: prints the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>` lines,
//! ordered by count descending, then by word ascending (byte order).

const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;

/// Maps a lowercase word to its number of occurrences. Keys borrow from the
/// text passed to `countWords`.
pub const Counts = std.StringHashMapUnmanaged(u64);

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Count descending, then word ascending.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

/// Lowercases ASCII letters in `text` in place and counts every word in it.
/// The returned keys are slices of `text`, which must outlive the map.
pub fn countWords(gpa: Allocator, text: []u8) Allocator.Error!Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < text.len) {
        if (!std.ascii.isAlphabetic(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {
            text[i] = std.ascii.toLower(text[i]);
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
    }
    return counts;
}

/// Returns up to `buf.len` most frequent entries, best first, stored in `buf`.
pub fn topWords(counts: *const Counts, buf: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buf.len and !entry.before(buf[len - 1])) continue;

        // Insertion into the small sorted prefix, dropping the worst if full.
        var pos = if (len < buf.len) len else len - 1;
        while (pos > 0 and entry.before(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = entry;
        if (len < buf.len) len += 1;
    }
    return buf[0..len];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var read_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &read_buf);
    const text = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &top_buf);

    var write_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &write_buf);
    const out = &stdout.interface;
    for (top) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, input);
    defer gpa.free(text);
    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);
    var buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &buf);
    try std.testing.expectEqual(expected.len, top.len);
    for (expected, top) |want, got| {
        try std.testing.expectEqualStrings(want.word, got.word);
        try std.testing.expectEqual(want.count, got.count);
    }
}

test "spec example" {
    try expectTop("The cat and the hat.", &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators and non-ascii bytes" {
    try expectTop("don't stop_me 4now, now-NOW\xffnow\xc3(", &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    });
}

test "empty input" {
    try expectTop("", &.{});
    try expectTop("123 ... \n", &.{});
}

test "keeps only the ten best with ties by word" {
    try expectTop("zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha", &.{
        .{ .word = "alpha", .count = 2 },
        .{ .word = "beta", .count = 1 },
        .{ .word = "eta", .count = 1 },
        .{ .word = "iota", .count = 1 },
        .{ .word = "kappa", .count = 1 },
        .{ .word = "lambda", .count = 1 },
        .{ .word = "mu", .count = 1 },
        .{ .word = "nu", .count = 1 },
        .{ .word = "omicron", .count = 1 },
        .{ .word = "pi", .count = 1 },
    });
}
