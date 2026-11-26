//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Every other
//! byte is a separator. Output is `<count> <word>` per line, ordered by count
//! descending, ties broken by word ascending (byte order).

const std = @import("std");
const Allocator = std.mem.Allocator;

const top_n = 10;
const chunk_size = 64 * 1024;

/// Maps each byte to its lowercase ASCII letter, or 0 for separators.
const lower_table: [256]u8 = blk: {
    var table = [_]u8{0} ** 256;
    for ('A'..'Z' + 1) |c| table[c] = @intCast(c | 0x20);
    for ('a'..'z' + 1) |c| table[c] = @intCast(c);
    break :blk table;
};

/// Incrementally counts words across arbitrarily split chunks of bytes.
const WordCounter = struct {
    /// Owns the map's key bytes; freed all at once in `deinit`.
    arena: std.heap.ArenaAllocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Word fragment carried over from the previous chunk(s).
    pending: std.ArrayList(u8) = .empty,
    gpa: Allocator,

    fn init(gpa: Allocator) WordCounter {
        return .{ .arena = .init(gpa), .gpa = gpa };
    }

    fn deinit(self: *WordCounter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    fn add(self: *WordCounter, word: []const u8) Allocator.Error!void {
        const entry = try self.counts.getOrPut(self.gpa, word);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.key_ptr.* = self.arena.allocator().dupe(u8, word) catch |err| {
                self.counts.removeByPtr(entry.key_ptr);
                return err;
            };
            entry.value_ptr.* = 1;
        }
    }

    /// Counts the words in `chunk`, lowercasing it in place. A word that runs
    /// to the end of the chunk is held back until its end is seen.
    fn feed(self: *WordCounter, chunk: []u8) Allocator.Error!void {
        var start: ?usize = null;
        for (chunk, 0..) |byte, i| {
            const lower = lower_table[byte];
            if (lower != 0) {
                chunk[i] = lower;
                if (start == null) start = i;
            } else if (start) |s| {
                try self.emit(chunk[s..i]);
                start = null;
            } else if (self.pending.items.len != 0) {
                try self.flushPending();
            }
        }
        if (start) |s| try self.pending.appendSlice(self.gpa, chunk[s..]);
    }

    /// Counts a completed word, joining it to any carried-over fragment.
    fn emit(self: *WordCounter, word: []const u8) Allocator.Error!void {
        if (self.pending.items.len == 0) return self.add(word);
        try self.pending.appendSlice(self.gpa, word);
        try self.flushPending();
    }

    fn flushPending(self: *WordCounter) Allocator.Error!void {
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    /// Counts any trailing fragment; call once after the last chunk.
    fn finish(self: *WordCounter) Allocator.Error!void {
        if (self.pending.items.len != 0) try self.flushPending();
    }
};

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks before `b`: count descending, then word ascending.
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Selects the top `n` entries in rank order without sorting the whole map.
/// Returns the filled prefix of `out`.
fn topEntries(counts: *const std.StringHashMapUnmanaged(u64), out: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const candidate: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len) {
            if (out.len == 0 or !candidate.ranksBefore(out[len - 1])) continue;
            len -= 1;
        }
        var i = len;
        while (i > 0 and candidate.ranksBefore(out[i - 1])) : (i -= 1) {
            out[i] = out[i - 1];
        }
        out[i] = candidate;
        len += 1;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: WordCounter = .init(gpa);
    defer counter.deinit();

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &.{});
    const chunk = try gpa.alloc(u8, chunk_size);
    defer gpa.free(chunk);
    while (true) {
        const n = stdin_reader.interface.readSliceShort(chunk) catch |err| switch (err) {
            error.ReadFailed => return stdin_reader.err.?,
        };
        if (n == 0) break;
        try counter.feed(chunk[0..n]);
        if (n < chunk.len) break;
    }
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    const top = topEntries(&counter.counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
    try out.flush();
}

test "words split across chunks are joined" {
    var counter: WordCounter = .init(std.testing.allocator);
    defer counter.deinit();
    var a = "The ca".*;
    var b = "T and_the".*;
    var c = " HAT".*;
    try counter.feed(&a);
    try counter.feed(&b);
    try counter.feed(&c);
    try counter.finish();
    try std.testing.expectEqual(@as(u64, 2), counter.counts.get("the").?);
    try std.testing.expectEqual(@as(u64, 1), counter.counts.get("cat").?);
    try std.testing.expectEqual(@as(u64, 1), counter.counts.get("and").?);
    try std.testing.expectEqual(@as(u64, 1), counter.counts.get("hat").?);
    try std.testing.expectEqual(@as(u32, 4), counter.counts.count());
}

test "ranking orders by count then word" {
    var counter: WordCounter = .init(std.testing.allocator);
    defer counter.deinit();
    var text = "b a c b a d".*;
    try counter.feed(&text);
    try counter.finish();
    var buf: [3]Entry = undefined;
    const top = topEntries(&counter.counts, &buf);
    try std.testing.expectEqual(@as(usize, 3), top.len);
    try std.testing.expectEqualStrings("a", top[0].word);
    try std.testing.expectEqualStrings("b", top[1].word);
    try std.testing.expectEqualStrings("c", top[2].word);
}
