//! Counts case-folded ASCII words fed to it in arbitrary chunks.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words split across chunk boundaries are reassembled before being counted.

const std = @import("std");
const Allocator = std.mem.Allocator;

const WordCounter = @This();

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ranking order: count descending, then word ascending (byte order).
    pub fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

gpa: Allocator,
/// Owns the bytes of every key stored in `counts`.
words: std.heap.ArenaAllocator,
counts: std.StringHashMapUnmanaged(u64) = .empty,
/// Lowercased prefix of a word that ran up to the end of the previous chunk.
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

/// Counts the words in `chunk`. Letters in `chunk` are lowercased in place.
/// A word touching the end of `chunk` is held back until the next call to
/// `feed` or `finish` shows where it ends.
pub fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
    var i: usize = 0;

    if (self.pending.items.len > 0) {
        i = wordEnd(chunk, 0);
        lowercase(chunk[0..i]);
        try self.pending.appendSlice(self.gpa, chunk[0..i]);
        if (i == chunk.len) return;
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    while (true) {
        while (i < chunk.len and !std.ascii.isAlphabetic(chunk[i])) i += 1;
        if (i == chunk.len) return;

        const start = i;
        i = wordEnd(chunk, start);
        const word = chunk[start..i];
        lowercase(word);
        if (i == chunk.len) {
            try self.pending.appendSlice(self.gpa, word);
            return;
        }
        try self.add(word);
    }
}

/// Counts any word left pending at the end of the input.
pub fn finish(self: *WordCounter) Allocator.Error!void {
    if (self.pending.items.len == 0) return;
    try self.add(self.pending.items);
    self.pending.clearRetainingCapacity();
}

/// Writes the highest-ranked entries into `buffer` (best first) and returns
/// the filled prefix. Selection is a bounded insertion, so the map is never
/// sorted as a whole. Returned words are owned by the counter.
pub fn top(self: *const WordCounter, buffer: []Entry) []Entry {
    var len: usize = 0;
    var it = self.counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buffer.len) {
            if (len == 0 or !entry.ranksBefore(buffer[len - 1])) continue;
        } else {
            len += 1;
        }
        var pos = len - 1;
        while (pos > 0 and entry.ranksBefore(buffer[pos - 1])) : (pos -= 1) {
            buffer[pos] = buffer[pos - 1];
        }
        buffer[pos] = entry;
    }
    return buffer[0..len];
}

fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
    const gop = try self.counts.getOrPut(self.gpa, word);
    if (gop.found_existing) {
        gop.value_ptr.* += 1;
    } else {
        errdefer self.counts.removeByPtr(gop.key_ptr);
        gop.key_ptr.* = try self.words.allocator().dupe(u8, word);
        gop.value_ptr.* = 1;
    }
}

fn wordEnd(bytes: []const u8, start: usize) usize {
    var i = start;
    while (i < bytes.len and std.ascii.isAlphabetic(bytes[i])) i += 1;
    return i;
}

fn lowercase(letters: []u8) void {
    for (letters) |*c| c.* = std.ascii.toLower(c.*);
}

fn expectTop(chunks: []const []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    var counter: WordCounter = .init(gpa);
    defer counter.deinit();
    for (chunks) |chunk| {
        const copy = try gpa.dupe(u8, chunk);
        defer gpa.free(copy);
        try counter.feed(copy);
    }
    try counter.finish();

    var buffer: [10]Entry = undefined;
    const got = counter.top(&buffer);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |want, have| {
        try std.testing.expectEqualStrings(want.word, have.word);
        try std.testing.expectEqual(want.count, have.count);
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

test "separators include digits, underscores, apostrophes and high bytes" {
    try expectTop(&.{"don't stop_me 4now, now-NOW\xffnow\xc3(x"}, &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "x", .count = 1 },
    });
}

test "words spanning chunk boundaries are reassembled" {
    try expectTop(&.{ "He", "", "LL", "o wor", "ld hel", "lo" }, &.{
        .{ .word = "hello", .count = 2 },
        .{ .word = "world", .count = 1 },
    });
}

test "keeps only the top ten" {
    try expectTop(&.{"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha"}, &.{
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

test "no words" {
    try expectTop(&.{ "", "123 ... \x80\x81" }, &.{});
}
