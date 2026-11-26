//! wordfreq: read all of standard input and print the 10 most frequent words.
//!
//! A word is a maximal run of ASCII letters, folded to lower case. Words are
//! lower-cased in place inside the input buffer and counted in a hash map
//! whose keys are slices of that buffer, so scanning allocates nothing per word.

const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ordering for output: count descending, then word ascending (byte order).
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

pub const Counts = std.StringHashMapUnmanaged(u64);

/// Counts the words in `buf`, lower-casing its letters in place.
/// The returned map's keys borrow from `buf`.
pub fn countWords(gpa: Allocator, buf: []u8) Allocator.Error!Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < buf.len) {
        if (!std.ascii.isAlphabetic(buf[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < buf.len and std.ascii.isAlphabetic(buf[i])) : (i += 1) {
            buf[i] |= 0x20; // ASCII letters: setting bit 5 lower-cases.
        }
        const gop = try counts.getOrPut(gpa, buf[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
    return counts;
}

/// Writes the (at most `out.len`) highest-ranked entries of `counts` into
/// `out` in output order and returns the filled prefix.
pub fn topWords(counts: *const Counts, out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len) {
            if (len == 0 or !entry.before(out[len - 1])) continue;
        } else {
            len += 1;
        }
        // Insertion into the sorted prefix; the last slot is free or evicted.
        var pos = len - 1;
        while (pos > 0 and entry.before(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = entry;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var counts = try countWords(gpa, input);
    defer counts.deinit(gpa);

    var top: [top_n]Entry = undefined;
    const ranked = topWords(&counts, &top);

    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const w = &stdout.interface;
    for (ranked) |e| try w.print("{d} {s}\n", .{ e.count, e.word });
    try w.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const buf = try gpa.dupe(u8, input);
    defer gpa.free(buf);
    var counts = try countWords(gpa, buf);
    defer counts.deinit(gpa);
    var top: [top_n]Entry = undefined;
    const got = topWords(&counts, &top);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |want, have| {
        try std.testing.expectEqualStrings(want.word, have.word);
        try std.testing.expectEqual(want.count, have.count);
    }
}

test "simple" {
    try expectTop("The cat and the hat.", &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators and non-ASCII bytes" {
    try expectTop("don't stop_me 4now, now-NOW\xffa\xc3(A", &.{
        .{ .word = "now", .count = 3 },
        .{ .word = "a", .count = 2 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    });
}

test "empty and wordless input" {
    try expectTop("", &.{});
    try expectTop("123 _ '\x80\xff", &.{});
}

test "limit and ties" {
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
