//! wordfreq: prints the ten most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! `<count> <word>` per line, ordered by count descending, then word ascending.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;
const read_chunk_size = 256 * 1024;

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True when `a` ranks strictly before `b`: higher count first, then
    /// lexicographically smaller word.
    pub fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Incrementally counts lowercased words across arbitrarily split input chunks.
pub const WordCounter = struct {
    /// Owns the bytes of every key stored in `counts`.
    arena: std.heap.ArenaAllocator,
    gpa: Allocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Holds a word that may continue into the next chunk.
    pending: std.ArrayList(u8) = .empty,

    pub fn init(gpa: Allocator) WordCounter {
        return .{ .arena = .init(gpa), .gpa = gpa };
    }

    pub fn deinit(self: *WordCounter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Consumes `chunk`, lowercasing it in place. A word touching the end of
    /// the chunk is held back until the next call to `feed` or `finish`.
    pub fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                if (self.pending.items.len != 0) try self.flushPending();
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) : (i += 1) {
                chunk[i] |= 0x20; // ASCII letters: setting bit 5 lowercases.
            }
            const word = chunk[start..i];
            if (i == chunk.len) {
                try self.pending.appendSlice(self.gpa, word);
            } else if (self.pending.items.len != 0) {
                try self.pending.appendSlice(self.gpa, word);
                try self.flushPending();
            } else {
                try self.add(word);
            }
        }
    }

    /// Counts any word still held back from the final chunk.
    pub fn finish(self: *WordCounter) Allocator.Error!void {
        if (self.pending.items.len != 0) try self.flushPending();
    }

    fn flushPending(self: *WordCounter) Allocator.Error!void {
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = try self.arena.allocator().dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }

    /// Writes the `n` highest-ranked entries into `out` in rank order and
    /// returns the filled prefix. Runs in O(distinct words * n).
    pub fn top(self: *const WordCounter, out: []Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == out.len and (len == 0 or !entry.before(out[len - 1]))) continue;
            // Insertion into the sorted prefix, dropping the last if full.
            var pos = if (len < out.len) len else len - 1;
            while (pos > 0 and entry.before(out[pos - 1])) : (pos -= 1) {
                out[pos] = out[pos - 1];
            }
            out[pos] = entry;
            if (len < out.len) len += 1;
        }
        return out[0..len];
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: WordCounter = .init(gpa);
    defer counter.deinit();

    const buf = try gpa.alloc(u8, read_chunk_size);
    defer gpa.free(buf);

    const stdin = Io.File.stdin();
    while (true) {
        const n = stdin.readStreaming(io, &.{buf}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        try counter.feed(buf[0..n]);
    }
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    const winners = counter.top(&top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const w = &stdout.interface;
    for (winners) |e| try w.print("{d} {s}\n", .{ e.count, e.word });
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
        try counter.feed(copy[i..@min(copy.len, i + chunk_size)]);
    }
    try counter.finish();

    var buf: [top_n]Entry = undefined;
    const got = counter.top(&buf);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |want, have| {
        try std.testing.expectEqualStrings(want.word, have.word);
        try std.testing.expectEqual(want.count, have.count);
    }
}

test "spec example" {
    const want = [_]Entry{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    };
    for ([_]usize{ 1, 2, 3, 7, 1024 }) |chunk| try expectTop("The cat and the hat.", chunk, &want);
}

test "separators and non-ascii bytes" {
    const want = [_]Entry{
        .{ .word = "now", .count = 3 },
        .{ .word = "a", .count = 1 },
        .{ .word = "b", .count = 1 },
        .{ .word = "don", .count = 1 },
        .{ .word = "t", .count = 1 },
    };
    for ([_]usize{ 1, 4, 1024 }) |chunk| try expectTop("don't 4now, now-NOW a\xffb\xc3(\x00", chunk, &want);
}

test "empty input" {
    try expectTop("", 16, &.{});
    try expectTop("123 _-' \xff", 16, &.{});
}
