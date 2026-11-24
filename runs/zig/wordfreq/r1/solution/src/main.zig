//! wordfreq: reads all of standard input and prints the 10 most frequent
//! words. A word is a maximal run of ASCII letters, folded to lowercase.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks strictly before `b`: higher count first, then
    /// lexicographically smaller word.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

const Counter = struct {
    /// Owns the word keys; freed all at once.
    arena: std.heap.ArenaAllocator,
    gpa: Allocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Holds a word that straddles a read-buffer boundary.
    pending: std.ArrayList(u8) = .empty,

    fn init(gpa: Allocator) Counter {
        return .{ .arena = .init(gpa), .gpa = gpa };
    }

    fn deinit(self: *Counter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
    }

    fn add(self: *Counter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = try self.arena.allocator().dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }

    /// Tokenizes `chunk`, which is the next slice of input. The chunk is
    /// lowercased in place. A word running into the end of the chunk is
    /// buffered until a separator or `finish` terminates it.
    fn feed(self: *Counter, chunk: []u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                if (self.pending.items.len > 0) try self.flushPending();
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
            } else if (self.pending.items.len > 0) {
                try self.pending.appendSlice(self.gpa, word);
                try self.flushPending();
            } else {
                try self.add(word);
            }
        }
    }

    fn finish(self: *Counter) Allocator.Error!void {
        if (self.pending.items.len > 0) try self.flushPending();
    }

    fn flushPending(self: *Counter) Allocator.Error!void {
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    /// Writes the highest-ranked entries into `out`, best first, and
    /// returns the filled prefix.
    fn top(self: *const Counter, out: []Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == out.len and !e.before(out[len - 1])) continue;
            // Insertion into a small sorted array.
            var j: usize = if (len < out.len) len else len - 1;
            while (j > 0 and e.before(out[j - 1])) : (j -= 1) out[j] = out[j - 1];
            out[j] = e;
            if (len < out.len) len += 1;
        }
        return out[0..len];
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: Counter = .init(gpa);
    defer counter.deinit();

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const in = &stdin.interface;
    while (true) {
        const chunk = in.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin.err.?,
        };
        try counter.feed(chunk);
        in.toss(chunk.len);
    }
    try counter.finish();

    var best: [top_n]Entry = undefined;
    const ranked = counter.top(&best);

    var out_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;
    for (ranked) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    out.flush() catch return stdout.err.?;
}

test "counts, folds case, and ranks" {
    var c: Counter = .init(std.testing.allocator);
    defer c.deinit();
    var text = "The cat and the hat. don't".*;
    // Split across a word boundary to exercise `pending`.
    try c.feed(text[0..5]);
    try c.feed(text[5..]);
    try c.finish();
    var best: [top_n]Entry = undefined;
    const r = c.top(&best);
    try std.testing.expectEqual(@as(usize, 6), r.len);
    try std.testing.expectEqualStrings("the", r[0].word);
    try std.testing.expectEqual(@as(u64, 2), r[0].count);
    try std.testing.expectEqualStrings("and", r[1].word);
    try std.testing.expectEqualStrings("t", r[5].word);
}
