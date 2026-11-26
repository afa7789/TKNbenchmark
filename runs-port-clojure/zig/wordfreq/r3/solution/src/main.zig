//! wordfreq: prints the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase. Output lines are `<count> <word>`, ordered by
//! count descending and then by word ascending (byte order).

const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;
const read_buffer_size = 64 * 1024;

/// Accumulates lowercase word counts from a byte stream delivered in chunks.
/// Words may span chunk boundaries.
pub const WordCounter = struct {
    /// Word -> occurrence count. Keys are owned by `arena`.
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Backing storage for map keys; freed all at once in `deinit`.
    arena: std.heap.ArenaAllocator,
    /// The lowercase prefix of a word that ran off the end of the previous chunk.
    pending: std.ArrayList(u8) = .empty,
    gpa: Allocator,

    pub fn init(gpa: Allocator) WordCounter {
        return .{ .gpa = gpa, .arena = .init(gpa) };
    }

    pub fn deinit(self: *WordCounter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Consumes `chunk`, lowercasing it in place.
    pub fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                // A separator terminates any word carried over from the previous chunk.
                try self.flushPending();
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) : (i += 1) {
                chunk[i] = std.ascii.toLower(chunk[i]);
            }
            const word = chunk[start..i];
            if (i == chunk.len) {
                // The word may continue in the next chunk.
                try self.pending.appendSlice(self.gpa, word);
            } else if (self.pending.items.len > 0) {
                try self.pending.appendSlice(self.gpa, word);
                try self.flushPending();
            } else {
                try self.add(word);
            }
        }
    }

    /// Counts any word left over at end of input.
    pub fn finish(self: *WordCounter) Allocator.Error!void {
        try self.flushPending();
    }

    fn flushPending(self: *WordCounter) Allocator.Error!void {
        if (self.pending.items.len == 0) return;
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            errdefer self.counts.removeByPtr(gop.key_ptr);
            gop.key_ptr.* = try self.arena.allocator().dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }
};

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks ahead of `b`: higher count first, then word ascending.
    pub fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

/// Selects the `n` highest-ranked entries from `counts` into `out`, best first.
/// Returns the populated prefix of `out`. Runs in O(len(counts) * n).
pub fn topWords(counts: *const std.StringHashMapUnmanaged(u64), out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const candidate: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len and !candidate.ranksBefore(out[len - 1])) continue;
        // Insertion into the sorted prefix, dropping the last entry when full.
        var pos = if (len < out.len) len else out.len - 1;
        while (pos > 0 and candidate.ranksBefore(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = candidate;
        if (len < out.len) len += 1;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var counter: WordCounter = .init(init.gpa);
    defer counter.deinit();

    const stdin = std.Io.File.stdin();
    var buf: [read_buffer_size]u8 = undefined;
    while (true) {
        const n = stdin.readStreaming(io, &.{&buf}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        try counter.feed(buf[0..n]);
    }
    try counter.finish();

    var slots: [top_n]Entry = undefined;
    const top = topWords(&counter.counts, &slots);

    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    const w = &stdout.interface;
    for (top) |e| try w.print("{d} {s}\n", .{ e.count, e.word });
    try w.flush();
}

fn expectTop(input: []const u8, chunk_size: usize, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const copy = try gpa.dupe(u8, input);
    defer gpa.free(copy);

    var counter: WordCounter = .init(gpa);
    defer counter.deinit();
    var i: usize = 0;
    while (i < copy.len) : (i += chunk_size) {
        try counter.feed(copy[i..@min(i + chunk_size, copy.len)]);
    }
    try counter.finish();

    var slots: [top_n]Entry = undefined;
    const top = topWords(&counter.counts, &slots);
    try std.testing.expectEqual(expected.len, top.len);
    for (expected, top) |want, got| {
        try std.testing.expectEqualStrings(want.word, got.word);
        try std.testing.expectEqual(want.count, got.count);
    }
}

test "spec example" {
    const want = [_]Entry{
        .{ .word = "the", .count = 2 }, .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 }, .{ .word = "hat", .count = 1 },
    };
    for ([_]usize{ 1, 2, 3, 7, 1024 }) |chunk| try expectTop("The cat and the hat.", chunk, &want);
}

test "separators and case folding across chunk boundaries" {
    const input = "don't stop_me 4now, now-NOW\xffNoW\xc3(";
    const want = [_]Entry{
        .{ .word = "now", .count = 4 }, .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },  .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    };
    for ([_]usize{ 1, 2, 5, 1024 }) |chunk| try expectTop(input, chunk, &want);
}

test "empty and wordless input" {
    try expectTop("", 4, &.{});
    try expectTop("123 _ -- \x80\xff", 4, &.{});
}

test "keeps only top ten with ties by word" {
    const input = "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha";
    const want = [_]Entry{
        .{ .word = "alpha", .count = 2 },   .{ .word = "beta", .count = 1 },
        .{ .word = "eta", .count = 1 },     .{ .word = "iota", .count = 1 },
        .{ .word = "kappa", .count = 1 },   .{ .word = "lambda", .count = 1 },
        .{ .word = "mu", .count = 1 },      .{ .word = "nu", .count = 1 },
        .{ .word = "omicron", .count = 1 }, .{ .word = "pi", .count = 1 },
    };
    try expectTop(input, 3, &want);
}
