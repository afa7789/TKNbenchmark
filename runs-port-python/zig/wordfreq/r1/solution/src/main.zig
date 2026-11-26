//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending, ties broken by word ascending (byte order).

const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;

pub const Entry = struct {
    word: []const u8,
    count: usize,

    /// True when `a` ranks strictly ahead of `b` in the output order.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Counts words in `data`, lowercasing it in place so that map keys can
/// borrow directly from the input buffer without per-word allocations.
/// The returned map's keys alias `data`.
pub fn countWords(gpa: Allocator, data: []u8) Allocator.Error!std.StringHashMapUnmanaged(usize) {
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < data.len) {
        if (!std.ascii.isAlphabetic(data[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < data.len and std.ascii.isAlphabetic(data[i])) : (i += 1) {
            data[i] |= 0x20; // ASCII letters: setting bit 5 lowercases.
        }
        const gop = try counts.getOrPut(gpa, data[start..i]);
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
    }
    return counts;
}

/// Selects up to `out.len` best-ranked entries into `out` (sorted) and
/// returns the filled prefix. Runs in O(distinct words * out.len).
pub fn topWords(counts: *const std.StringHashMapUnmanaged(usize), out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const candidate: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len and !candidate.before(out[len - 1])) continue;

        // Insertion into the sorted prefix, dropping the last element if full.
        var pos = if (len < out.len) len else len - 1;
        while (pos > 0 and candidate.before(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = candidate;
        if (len < out.len) len += 1;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const data = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(data);

    var counts = try countWords(gpa, data);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| {
        try out.print("{d} {s}\n", .{ entry.count, entry.word });
    }
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const data = try gpa.dupe(u8, input);
    defer gpa.free(data);
    var counts = try countWords(gpa, data);
    defer counts.deinit(gpa);
    var buf: [top_n]Entry = undefined;
    const got = topWords(&counts, &buf);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try std.testing.expectEqualStrings(e.word, g.word);
        try std.testing.expectEqual(e.count, g.count);
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
    try expectTop("don't stop_me 4now, now-NOW\xc3\xa9now\xff", &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    });
}

test "empty input" {
    try expectTop("", &.{});
    try expectTop("123 _ !?", &.{});
}

test "top ten cutoff with ties" {
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
