//! Streaming word counter.
//!
//! Input is fed in arbitrary chunks; a word split across a chunk boundary is
//! carried over and counted once it ends. A word is a maximal run of ASCII
//! letters, folded to lowercase; every other byte is a separator.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Counter = @This();

/// Number of occurrences of each distinct lowercase word. Keys are owned by
/// `key_arena`.
counts: std.StringHashMapUnmanaged(u64) = .empty,
/// Backing storage for the map keys, freed all at once in `deinit`.
key_arena: std.heap.ArenaAllocator,
/// The lowercased word currently being accumulated; non-empty only while the
/// most recently fed byte was a letter.
word: std.ArrayList(u8) = .empty,

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ordering of the report: count descending, then word ascending.
    pub fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

pub fn init(gpa: Allocator) Counter {
    return .{ .key_arena = .init(gpa) };
}

pub fn deinit(c: *Counter, gpa: Allocator) void {
    c.counts.deinit(gpa);
    c.key_arena.deinit();
    c.word.deinit(gpa);
    c.* = undefined;
}

/// Processes the next chunk of input.
pub fn feed(c: *Counter, gpa: Allocator, chunk: []const u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < chunk.len) {
        // Skip separators.
        while (i < chunk.len and !std.ascii.isAlphabetic(chunk[i])) i += 1;
        if (i > 0 and c.word.items.len > 0) {
            // The chunk began with a separator, ending the carried-over word.
            try c.flush(gpa);
        }
        const start = i;
        while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) i += 1;
        if (i == start) break;

        const run = chunk[start..i];
        const dest = try c.word.addManyAsSlice(gpa, run.len);
        for (dest, run) |*d, s| d.* = std.ascii.toLower(s);

        // A run reaching the end of the chunk may continue in the next one.
        if (i < chunk.len) try c.flush(gpa);
    }
}

/// Signals end of input, counting any word still being accumulated.
pub fn finish(c: *Counter, gpa: Allocator) Allocator.Error!void {
    if (c.word.items.len > 0) try c.flush(gpa);
}

fn flush(c: *Counter, gpa: Allocator) Allocator.Error!void {
    const gop = try c.counts.getOrPut(gpa, c.word.items);
    if (gop.found_existing) {
        gop.value_ptr.* += 1;
    } else {
        gop.key_ptr.* = try c.key_arena.allocator().dupe(u8, c.word.items);
        gop.value_ptr.* = 1;
    }
    c.word.clearRetainingCapacity();
}

/// Writes the most frequent words into `buf`, best first per `Entry.before`,
/// and returns the filled prefix. At most `buf.len` entries are returned.
/// Runs in O(distinct words × buf.len), which beats a full sort for small `buf`.
pub fn top(c: *const Counter, buf: []Entry) []Entry {
    var len: usize = 0;
    var it = c.counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buf.len and (len == 0 or !entry.before(buf[len - 1]))) continue;

        // Insertion into the sorted prefix, dropping the last entry if full.
        var pos = if (len < buf.len) len else len - 1;
        while (pos > 0 and entry.before(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = entry;
        if (len < buf.len) len += 1;
    }
    return buf[0..len];
}

fn expectTop(chunks: []const []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    var c: Counter = .init(gpa);
    defer c.deinit(gpa);
    for (chunks) |chunk| try c.feed(gpa, chunk);
    try c.finish(gpa);

    var buf: [10]Entry = undefined;
    const got = c.top(&buf);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try std.testing.expectEqualStrings(e.word, g.word);
        try std.testing.expectEqual(e.count, g.count);
    }
}

test "spec example" {
    try expectTop(&.{"The cat and the hat."}, &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators and case folding" {
    try expectTop(&.{"don't stop_me 4now, now-NOW\xc3\xa9x"}, &.{
        .{ .word = "now", .count = 3 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "x", .count = 1 },
    });
}

test "words split across chunks" {
    try expectTop(&.{ "ab", "C", "", "d ab", "cd", " x", "y" }, &.{
        .{ .word = "abcd", .count = 2 },
        .{ .word = "xy", .count = 1 },
    });
}

test "no words" {
    try expectTop(&.{ "", "123 ,.!", "\x00\xff" }, &.{});
}

test "keeps only the top ten" {
    try expectTop(&.{"k j i h g f e d c b a a l l m m m"}, &.{
        .{ .word = "m", .count = 3 },
        .{ .word = "a", .count = 2 },
        .{ .word = "l", .count = 2 },
        .{ .word = "b", .count = 1 },
        .{ .word = "c", .count = 1 },
        .{ .word = "d", .count = 1 },
        .{ .word = "e", .count = 1 },
        .{ .word = "f", .count = 1 },
        .{ .word = "g", .count = 1 },
        .{ .word = "h", .count = 1 },
    });
}
