//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const top_n = 10;

/// Returns the lowercase form of `byte` if it is an ASCII letter, otherwise null.
inline fn foldLetter(byte: u8) ?u8 {
    const lower = byte | 0x20;
    return if (lower >= 'a' and lower <= 'z') lower else null;
}

/// Incrementally tokenizes byte chunks into lowercase words and counts them.
/// Word keys are owned by `arena`; the map itself lives in `gpa`.
const WordCounter = struct {
    gpa: Allocator,
    arena: Allocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Word fragment carried over from the end of the previous chunk.
    pending: std.ArrayList(u8) = .empty,

    fn deinit(self: *WordCounter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
    }

    /// Consumes `chunk`, lowercasing letters in place.
    fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
        var start: ?usize = null;
        for (chunk, 0..) |byte, i| {
            if (foldLetter(byte)) |lower| {
                chunk[i] = lower;
                if (start == null) start = i;
            } else if (start) |s| {
                try self.add(chunk[s..i]);
                start = null;
            } else if (self.pending.items.len != 0) {
                try self.flushPending();
            }
        }
        if (start) |s| try self.pending.appendSlice(self.gpa, chunk[s..]);
    }

    /// Counts any trailing word fragment; call once after the last chunk.
    fn finish(self: *WordCounter) Allocator.Error!void {
        if (self.pending.items.len != 0) try self.flushPending();
    }

    fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
        if (self.pending.items.len == 0) return self.increment(word);
        try self.pending.appendSlice(self.gpa, word);
        try self.flushPending();
    }

    fn flushPending(self: *WordCounter) Allocator.Error!void {
        try self.increment(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    fn increment(self: *WordCounter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            errdefer self.counts.removeByPtr(gop.key_ptr);
            gop.key_ptr.* = try self.arena.dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }
};

const Entry = struct {
    word: []const u8,
    count: u64,

    /// Count descending, then word ascending in byte order.
    fn lessThan(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Selects the best `out.len` entries into `out` (sorted) without sorting the
/// whole map. Returns the filled prefix.
fn topEntries(counts: *const std.StringHashMapUnmanaged(u64), out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len) {
            if (!entry.lessThan(out[len - 1])) continue;
        } else {
            len += 1;
        }
        var pos = len - 1;
        while (pos > 0 and entry.lessThan(out[pos - 1])) : (pos -= 1) {
            out[pos] = out[pos - 1];
        }
        out[pos] = entry;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: WordCounter = .{ .gpa = gpa, .arena = init.arena.allocator() };
    defer counter.deinit();

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buf);
    const reader = &stdin_reader.interface;
    while (true) {
        const chunk = reader.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin_reader.err.?,
        };
        try counter.feed(chunk);
        reader.toss(chunk.len);
    }
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    const top = topEntries(&counter.counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| {
        out.print("{d} {s}\n", .{ entry.count, entry.word }) catch return stdout_writer.err.?;
    }
    out.flush() catch return stdout_writer.err.?;
}

test "counts words across chunk boundaries" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var counter: WordCounter = .{ .gpa = std.testing.allocator, .arena = arena.allocator() };
    defer counter.deinit();

    var a = "The ca".*;
    var b = "t and THE hat.".*;
    try counter.feed(&a);
    try counter.feed(&b);
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    const top = topEntries(&counter.counts, &top_buf);
    try std.testing.expectEqual(@as(usize, 4), top.len);
    try std.testing.expectEqualStrings("the", top[0].word);
    try std.testing.expectEqual(@as(u64, 2), top[0].count);
    try std.testing.expectEqualStrings("and", top[1].word);
    try std.testing.expectEqualStrings("cat", top[2].word);
    try std.testing.expectEqualStrings("hat", top[3].word);
}
