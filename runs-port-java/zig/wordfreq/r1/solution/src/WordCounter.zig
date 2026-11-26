//! Counts case-insensitive occurrences of ASCII words fed in arbitrary chunks.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase. Word bytes are copied once, on first sight,
//! into an arena owned by the counter.

const std = @import("std");
const Allocator = std.mem.Allocator;

const WordCounter = @This();

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks ahead of `b`: higher count first, then byte-wise smaller word.
    pub fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

gpa: Allocator,
/// Backing storage for the map keys.
words: std.heap.ArenaAllocator,
counts: std.StringHashMapUnmanaged(u64) = .empty,
/// Letters of a word that may continue into the next chunk.
pending: std.ArrayList(u8) = .empty,

pub fn init(gpa: Allocator) WordCounter {
    return .{ .gpa = gpa, .words = .init(gpa) };
}

pub fn deinit(self: *WordCounter) void {
    self.counts.deinit(self.gpa);
    self.pending.deinit(self.gpa);
    self.words.deinit();
    self.* = undefined;
}

/// Tokenizes `chunk` and counts its words. Letters in `chunk` are lowercased in
/// place. A word at the end of the chunk is held back until a separator, the
/// next chunk, or `finish` shows where it ends.
pub fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < chunk.len) {
        const start = i;
        while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) : (i += 1) {
            chunk[i] |= 0x20; // ASCII lowercase
        }
        const run = chunk[start..i];

        if (i == chunk.len) {
            try self.pending.appendSlice(self.gpa, run);
            return;
        }

        // chunk[i] is a separator, so any word in progress ends here.
        if (self.pending.items.len > 0) {
            try self.pending.appendSlice(self.gpa, run);
            try self.add(self.pending.items);
            self.pending.clearRetainingCapacity();
        } else if (run.len > 0) {
            try self.add(run);
        }
        i += 1;
    }
}

/// Counts the word held back at the end of the last chunk, if any.
pub fn finish(self: *WordCounter) Allocator.Error!void {
    if (self.pending.items.len == 0) return;
    try self.add(self.pending.items);
    self.pending.clearRetainingCapacity();
}

/// Records one occurrence of the lowercase `word`.
fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
    const gop = try self.counts.getOrPut(self.gpa, word);
    if (!gop.found_existing) {
        errdefer self.counts.removeByPtr(gop.key_ptr);
        gop.key_ptr.* = try self.words.allocator().dupe(u8, word);
        gop.value_ptr.* = 0;
    }
    gop.value_ptr.* += 1;
}

/// Fills `out` with the `out.len` best-ranked words (see `Entry.ranksBefore`),
/// in rank order, and returns the filled prefix. Returned words borrow from
/// the counter.
pub fn top(self: *const WordCounter, out: []Entry) []Entry {
    if (out.len == 0) return out[0..0];
    var len: usize = 0;
    var it = self.counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        var j: usize = undefined;
        if (len < out.len) {
            j = len;
            len += 1;
        } else if (entry.ranksBefore(out[len - 1])) {
            j = len - 1; // evict the current worst
        } else {
            continue;
        }
        while (j > 0 and entry.ranksBefore(out[j - 1])) : (j -= 1) {
            out[j] = out[j - 1];
        }
        out[j] = entry;
    }
    return out[0..len];
}

fn expectTop(chunks: []const []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    var counter: WordCounter = .init(gpa);
    defer counter.deinit();
    for (chunks) |c| {
        const copy = try gpa.dupe(u8, c);
        defer gpa.free(copy);
        try counter.feed(copy);
    }
    try counter.finish();

    var buf: [10]Entry = undefined;
    const got = counter.top(&buf);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try std.testing.expectEqualStrings(e.word, g.word);
        try std.testing.expectEqual(e.count, g.count);
    }
}

test "counts and ranks words" {
    try expectTop(&.{"The cat and the hat."}, &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators and non-ASCII bytes" {
    try expectTop(&.{"don't stop_me 4now, now-NOW\xffnow\xc3(x@[`{"}, &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "x", .count = 1 },
    });
}

test "words spanning chunk boundaries" {
    try expectTop(&.{ "he", "", "LLo wo", "rld", " hel", "lo" }, &.{
        .{ .word = "hello", .count = 2 },
        .{ .word = "world", .count = 1 },
    });
}

test "empty input" {
    try expectTop(&.{ "", " 123 ...\n" }, &.{});
}

test "keeps only the top ten" {
    try expectTop(&.{"l k j i h g f e d c b a a"}, &.{
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
