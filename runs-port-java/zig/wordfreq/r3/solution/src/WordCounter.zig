//! Counts case-insensitive ASCII words. A word is a maximal run of `A-Z` / `a-z`;
//! every other byte is a separator.
//!
//! Words are folded to lowercase in place and the table stores slices into the
//! caller's text, so no per-word allocation happens. The text must outlive the
//! counter.

const std = @import("std");
const Allocator = std.mem.Allocator;

const WordCounter = @This();

pub const WordCount = struct {
    word: []const u8,
    count: u64,

    /// Ordering used for ranking: count descending, then word ascending (byte order).
    pub fn ranksBefore(a: WordCount, b: WordCount) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

counts: std.StringHashMapUnmanaged(u64) = .empty,

pub fn deinit(self: *WordCounter, gpa: Allocator) void {
    self.counts.deinit(gpa);
    self.* = undefined;
}

/// Tokenizes `text`, folding letters to lowercase in place, and records every word.
pub fn addText(self: *WordCounter, gpa: Allocator, text: []u8) Allocator.Error!void {
    var start: ?usize = null;
    for (text, 0..) |*byte, i| {
        const lower = byte.* | 0x20;
        if (lower >= 'a' and lower <= 'z') {
            byte.* = lower;
            if (start == null) start = i;
        } else if (start) |s| {
            try self.addWord(gpa, text[s..i]);
            start = null;
        }
    }
    if (start) |s| try self.addWord(gpa, text[s..]);
}

/// Records one occurrence of `word`, which must already be lowercase.
pub fn addWord(self: *WordCounter, gpa: Allocator, word: []const u8) Allocator.Error!void {
    const entry = try self.counts.getOrPut(gpa, word);
    if (entry.found_existing) {
        entry.value_ptr.* += 1;
    } else {
        entry.value_ptr.* = 1;
    }
}

/// Fills `out` with the highest-ranked words in rank order and returns the
/// populated prefix (shorter than `out` if there are fewer distinct words).
pub fn top(self: *const WordCounter, out: []WordCount) []WordCount {
    var len: usize = 0;
    var it = self.counts.iterator();
    while (it.next()) |entry| {
        const candidate: WordCount = .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* };
        if (len == out.len) {
            if (len == 0 or !candidate.ranksBefore(out[len - 1])) continue;
            len -= 1; // Drop the worst retained entry to make room.
        }
        // Insertion into the sorted prefix; `out` is small, so this is cheap.
        var i = len;
        while (i > 0 and candidate.ranksBefore(out[i - 1])) : (i -= 1) {
            out[i] = out[i - 1];
        }
        out[i] = candidate;
        len += 1;
    }
    return out[0..len];
}

fn expectTop(input: []const u8, comptime n: usize, expected: []const WordCount) !void {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, input);
    defer gpa.free(text);

    var counter: WordCounter = .{};
    defer counter.deinit(gpa);
    try counter.addText(gpa, text);

    var buf: [n]WordCount = undefined;
    const got = counter.top(&buf);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |want, have| {
        try std.testing.expectEqualStrings(want.word, have.word);
        try std.testing.expectEqual(want.count, have.count);
    }
}

test "counts and ranks words" {
    try expectTop("The cat and the hat.", 10, &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "non-letters separate words" {
    try expectTop("don't stop_me 4now, now-NOW\xffnow\xc3(x", 10, &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "x", .count = 1 },
    });
}

test "keeps only the best entries" {
    try expectTop("e d c b a a e", 3, &.{
        .{ .word = "a", .count = 2 },
        .{ .word = "e", .count = 2 },
        .{ .word = "b", .count = 1 },
    });
}

test "bytes adjacent to letters are separators" {
    try expectTop("@[`{ab", 10, &.{.{ .word = "ab", .count = 1 }});
}

test "no words" {
    try expectTop("", 10, &.{});
    try expectTop("123 _ !?", 10, &.{});
}
