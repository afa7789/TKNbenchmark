//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte separates words.
//! Words are folded to lowercase and reported as `<count> <word>`, ordered by
//! count descending, then by word ascending (byte order).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True when `a` ranks strictly before `b` in the output order.
    pub fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Accumulates lowercase word counts from a byte stream fed in arbitrary chunks.
pub const Counter = struct {
    /// Owns the word keys stored in `counts`.
    arena: std.heap.ArenaAllocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Letters of a word that may continue into the next chunk.
    pending: std.ArrayList(u8) = .empty,
    gpa: Allocator,

    pub fn init(gpa: Allocator) Counter {
        return .{ .arena = .init(gpa), .gpa = gpa };
    }

    pub fn deinit(self: *Counter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Feeds the next chunk of input. Words may span chunk boundaries.
    pub fn feed(self: *Counter, chunk: []const u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                if (self.pending.items.len != 0) {
                    try self.add(self.pending.items);
                    self.pending.clearRetainingCapacity();
                }
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) i += 1;
            const run = chunk[start..i];
            if (i == chunk.len) {
                // The word may continue in the next chunk.
                try self.appendLower(run);
            } else if (self.pending.items.len != 0) {
                try self.appendLower(run);
                try self.add(self.pending.items);
                self.pending.clearRetainingCapacity();
            } else {
                try self.addLowering(run);
            }
        }
    }

    /// Flushes any word left pending at end of input.
    pub fn finish(self: *Counter) Allocator.Error!void {
        if (self.pending.items.len != 0) {
            try self.add(self.pending.items);
            self.pending.clearRetainingCapacity();
        }
    }

    /// Returns up to `out.len` entries in output order. Entry words borrow from `self`.
    pub fn top(self: *const Counter, out: []Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == out.len and !e.before(out[len - 1])) continue;
            // Insertion into the small sorted prefix, dropping the last if full.
            var j = if (len < out.len) len else len - 1;
            while (j > 0 and e.before(out[j - 1])) : (j -= 1) out[j] = out[j - 1];
            out[j] = e;
            if (len < out.len) len += 1;
        }
        return out[0..len];
    }

    fn appendLower(self: *Counter, run: []const u8) Allocator.Error!void {
        const dest = try self.pending.addManyAsSlice(self.gpa, run.len);
        _ = std.ascii.lowerString(dest, run);
    }

    /// Counts a word that is not yet lowercased, avoiding a copy when possible.
    fn addLowering(self: *Counter, run: []const u8) Allocator.Error!void {
        var buf: [64]u8 = undefined;
        if (run.len <= buf.len) return self.add(std.ascii.lowerString(&buf, run));
        try self.appendLower(run);
        try self.add(self.pending.items);
        self.pending.clearRetainingCapacity();
    }

    /// Counts an already-lowercased word; `word` need not outlive the call.
    fn add(self: *Counter, word: []const u8) Allocator.Error!void {
        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = self.arena.allocator().dupe(u8, word) catch |err| {
                self.counts.removeByPtr(gop.key_ptr);
                return err;
            };
            gop.value_ptr.* = 1;
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var counter: Counter = .init(gpa);
    defer counter.deinit();

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buf);
    const in = &stdin_reader.interface;
    while (true) {
        in.fillMore() catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin_reader.err.?,
        };
        try counter.feed(in.buffered());
        in.tossBuffered();
    }
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    const top = counter.top(&top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    for (top) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    try out.flush();
}

fn expectTop(input: []const u8, chunk_len: usize, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    var counter: Counter = .init(gpa);
    defer counter.deinit();
    var rest = input;
    while (rest.len > 0) {
        const n = @min(chunk_len, rest.len);
        try counter.feed(rest[0..n]);
        rest = rest[n..];
    }
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    for (counter.top(&top_buf)) |e| try out.writer.print("{d} {s}\n", .{ e.count, e.word });
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    for ([_]usize{ 1, 2, 3, 1000 }) |n|
        try expectTop("The cat and the hat.", n, "2 the\n1 and\n1 cat\n1 hat\n");
}

test "separators and folding" {
    for ([_]usize{ 1, 5, 1000 }) |n|
        try expectTop("don't stop_me 4now, now-NOW\xffNoW\xc3(", n, "4 now\n1 don\n1 me\n1 stop\n1 t\n");
}

test "top ten with ties" {
    try expectTop(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        7,
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}

test "long words and empty input" {
    try expectTop("", 4, "");
    try expectTop("123 ... \xff", 4, "");
    const long = "A" ** 100 ++ " " ++ "a" ** 100;
    try expectTop(long, 1000, "2 " ++ "a" ** 100 ++ "\n");
    try expectTop(long, 7, "2 " ++ "a" ** 100 ++ "\n");
}
