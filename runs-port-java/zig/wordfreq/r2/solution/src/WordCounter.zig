//! Counts occurrences of lowercase ASCII words.
//!
//! Word bytes are copied once into an arena when a word is first seen, so
//! repeated words cost only a hash lookup.

const std = @import("std");
const Allocator = std.mem.Allocator;

const WordCounter = @This();

/// A word together with its occurrence count.
pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Orders by count descending, then by word ascending (byte order).
    fn moreFrequent(_: void, a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

arena: std.heap.ArenaAllocator,
counts: std.StringHashMapUnmanaged(u64) = .empty,

pub fn init(gpa: Allocator) WordCounter {
    return .{ .arena = .init(gpa) };
}

pub fn deinit(self: *WordCounter) void {
    self.counts.deinit(self.arena.child_allocator);
    self.arena.deinit();
    self.* = undefined;
}

/// Records one occurrence of `word`. The slice is copied if the word is new,
/// so the caller may reuse its memory afterwards.
pub fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
    const gop = try self.counts.getOrPut(self.arena.child_allocator, word);
    if (gop.found_existing) {
        gop.value_ptr.* += 1;
    } else {
        errdefer self.counts.removeByPtr(gop.key_ptr);
        gop.key_ptr.* = try self.arena.allocator().dupe(u8, word);
        gop.value_ptr.* = 1;
    }
}

/// Returns the `limit` most frequent words, by count descending then word
/// ascending. The returned slice is owned by the caller and must be freed
/// with `gpa`; the words it references stay valid until `deinit`.
pub fn top(self: *const WordCounter, gpa: Allocator, limit: usize) Allocator.Error![]Entry {
    const entries = try gpa.alloc(Entry, self.counts.count());
    errdefer gpa.free(entries);

    var it = self.counts.iterator();
    var i: usize = 0;
    while (it.next()) |kv| : (i += 1) {
        entries[i] = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
    }

    std.sort.pdq(Entry, entries, {}, Entry.moreFrequent);

    const n = @min(limit, entries.len);
    if (n == entries.len) return entries;
    return gpa.realloc(entries, n) catch entries[0..n];
}

/// Splits a byte stream into words (maximal runs of ASCII letters), folds
/// them to lowercase and counts them. Words may span chunk boundaries.
pub const Tokenizer = struct {
    counter: *WordCounter,
    word: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Tokenizer) void {
        self.word.deinit(self.counter.arena.child_allocator);
        self.* = undefined;
    }

    /// Feeds the next chunk of input.
    pub fn feed(self: *Tokenizer, chunk: []const u8) Allocator.Error!void {
        const gpa = self.counter.arena.child_allocator;
        for (chunk) |byte| {
            if (std.ascii.isAlphabetic(byte)) {
                try self.word.append(gpa, std.ascii.toLower(byte));
            } else {
                try self.flush();
            }
        }
    }

    /// Counts the pending word, if any. Call once after the last chunk.
    pub fn flush(self: *Tokenizer) Allocator.Error!void {
        if (self.word.items.len == 0) return;
        try self.counter.add(self.word.items);
        self.word.clearRetainingCapacity();
    }
};

fn expectTop(input: []const []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    var counter: WordCounter = .init(gpa);
    defer counter.deinit();
    var tokenizer: Tokenizer = .{ .counter = &counter };
    defer tokenizer.deinit();
    for (input) |chunk| try tokenizer.feed(chunk);
    try tokenizer.flush();

    const entries = try counter.top(gpa, 10);
    defer gpa.free(entries);
    try std.testing.expectEqual(expected.len, entries.len);
    for (expected, entries) |want, got| {
        try std.testing.expectEqualStrings(want.word, got.word);
        try std.testing.expectEqual(want.count, got.count);
    }
}

test "counts, folds case and breaks ties by word" {
    try expectTop(&.{"The cat and the hat."}, &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "non-letter bytes separate words" {
    try expectTop(&.{"don't stop_me 4now, now-NOW\xffnow\xc3(x@y[z`"}, &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "x", .count = 1 },
        .{ .word = "y", .count = 1 },
        .{ .word = "z", .count = 1 },
    });
}

test "words span chunk boundaries" {
    try expectTop(&.{ "hel", "LO wor", "", "ld hello" }, &.{
        .{ .word = "hello", .count = 2 },
        .{ .word = "world", .count = 1 },
    });
}

test "empty input yields nothing" {
    try expectTop(&.{ "", "123 ... _" }, &.{});
}

test "limits output to ten entries" {
    try expectTop(&.{"a b c d e f g h i j k l a"}, &.{
        .{ .word = "a", .count = 2 },
        .{ .word = "b", .count = 1 },
        .{ .word = "c", .count = 1 },
        .{ .word = "d", .count = 1 },
        .{ .word = "e", .count = 1 },
        .{ .word = "f", .count = 1 },
        .{ .word = "g", .count = 1 },
        .{ .word = "h", .count = 1 },
        .{ .word = "i", .count = 1 },
        .{ .word = "j", .count = 1 },
    });
}
