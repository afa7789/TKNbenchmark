//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase. Output is `<count> <word>` per line, ordered
//! by count descending, ties broken by word ascending (byte order).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const top_n = 10;
const chunk_size = 1 << 20;

const Counts = std.StringHashMapUnmanaged(u64);

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True when `a` ranks ahead of `b`: higher count first, then lexicographic word.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Accumulates word counts from a byte stream that may split words across chunks.
const Counter = struct {
    /// Owns the word keys stored in `counts`.
    arena: Allocator,
    /// Backs the hash map and the carry buffer.
    gpa: Allocator,
    counts: Counts = .empty,
    /// Lowercased prefix of a word that ran up to the end of the previous chunk.
    carry: std.ArrayList(u8) = .empty,

    fn deinit(self: *Counter) void {
        self.counts.deinit(self.gpa);
        self.carry.deinit(self.gpa);
    }

    fn add(self: *Counter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = try self.arena.dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }

    /// Lowercases `chunk` in place and counts every word it completes.
    fn feed(self: *Counter, chunk: []u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                if (self.carry.items.len != 0) {
                    try self.add(self.carry.items);
                    self.carry.clearRetainingCapacity();
                }
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) : (i += 1) {
                chunk[i] |= 0x20; // ASCII letters only: setting bit 5 lowercases.
            }
            const run = chunk[start..i];
            if (i == chunk.len) {
                // The word may continue in the next chunk.
                try self.carry.appendSlice(self.gpa, run);
            } else if (self.carry.items.len != 0) {
                try self.carry.appendSlice(self.gpa, run);
                try self.add(self.carry.items);
                self.carry.clearRetainingCapacity();
            } else {
                try self.add(run);
            }
        }
    }

    /// Counts any word left pending at end of input.
    fn finish(self: *Counter) Allocator.Error!void {
        if (self.carry.items.len != 0) {
            try self.add(self.carry.items);
            self.carry.clearRetainingCapacity();
        }
    }

    /// Returns the highest-ranked entries (at most `top_n`), best first.
    fn top(self: *const Counter, out: *[top_n]Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == top_n and !entry.before(out[len - 1])) continue;
            // Insertion into a small sorted array; drop the last entry if full.
            var pos = if (len < top_n) len else top_n - 1;
            while (pos > 0 and entry.before(out[pos - 1])) : (pos -= 1) {
                out[pos] = out[pos - 1];
            }
            out[pos] = entry;
            if (len < top_n) len += 1;
        }
        return out[0..len];
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: Counter = .{ .arena = init.arena.allocator(), .gpa = gpa };
    defer counter.deinit();

    const chunk = try gpa.alloc(u8, chunk_size);
    defer gpa.free(chunk);

    var stdin_reader = Io.File.stdin().readerStreaming(io, &.{});
    const reader = &stdin_reader.interface;
    while (true) {
        const n = reader.readSliceShort(chunk) catch return stdin_reader.err orelse error.ReadFailed;
        if (n == 0) break;
        try counter.feed(chunk[0..n]);
    }
    try counter.finish();

    var best: [top_n]Entry = undefined;
    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (counter.top(&best)) |entry| {
        try out.print("{d} {s}\n", .{ entry.count, entry.word });
    }
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var counter: Counter = .{ .arena = arena.allocator(), .gpa = std.testing.allocator };
    defer counter.deinit();

    // Feed one byte at a time to exercise words split across chunks.
    const buf = try std.testing.allocator.dupe(u8, input);
    defer std.testing.allocator.free(buf);
    for (0..buf.len) |i| try counter.feed(buf[i .. i + 1]);
    try counter.finish();

    var best: [top_n]Entry = undefined;
    const got = counter.top(&best);
    try std.testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| {
        try std.testing.expectEqualStrings(e.word, g.word);
        try std.testing.expectEqual(e.count, g.count);
    }
}

test "counts, folds case and breaks ties by word" {
    try expectTop("The cat and the hat.", &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators" {
    try expectTop("don't stop_me 4now, now-NOW\xffZ", &.{
        .{ .word = "now", .count = 3 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
        .{ .word = "z", .count = 1 },
    });
}

test "empty input" {
    try expectTop("", &.{});
    try expectTop("123 ._-\x80", &.{});
}
