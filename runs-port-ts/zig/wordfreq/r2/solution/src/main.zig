//! wordfreq: read all of standard input and print the 10 most frequent words.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! `<count> <word>` per line, ordered by count descending, then word ascending.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const top_n = 10;

pub const Counts = std.StringHashMapUnmanaged(u64);

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks strictly before `b`: higher count first, then
    /// lexicographically smaller word.
    pub fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Counts case-folded words in `data`, lowercasing the buffer in place.
/// Keys in the returned map borrow from `data`.
pub fn countWords(gpa: Allocator, data: []u8) Allocator.Error!Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < data.len) {
        while (i < data.len and !std.ascii.isAlphabetic(data[i])) i += 1;
        if (i == data.len) break;

        const start = i;
        while (i < data.len and std.ascii.isAlphabetic(data[i])) : (i += 1) {
            data[i] |= 0x20; // ASCII letters: setting bit 5 lowercases.
        }

        const gop = try counts.getOrPut(gpa, data[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
    return counts;
}

/// Selects the best `out.len` entries of `counts` into `out` in rank order,
/// without sorting the whole map. Returns the filled prefix of `out`.
pub fn topWords(counts: *const Counts, out: []Entry) []Entry {
    var len: usize = 0;
    if (out.len == 0) return out[0..0];

    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len and !entry.before(out[len - 1])) continue;

        var pos = if (len < out.len) blk: {
            len += 1;
            break :blk len - 1;
        } else out.len - 1;

        while (pos > 0 and entry.before(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = entry;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buf);
    const data = try stdin_reader.interface.allocRemaining(gpa, .unlimited);

    const counts = try countWords(gpa, data);

    var top_buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const data = try gpa.dupe(u8, input);
    defer gpa.free(data);

    var counts = try countWords(gpa, data);
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

test "separators and non-ASCII bytes" {
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
    try expectTop("123 !@# \x80\xff", &.{});
}

test "keeps only the top ten" {
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
