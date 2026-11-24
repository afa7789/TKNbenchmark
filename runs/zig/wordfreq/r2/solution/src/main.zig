//! wordfreq: read stdin, print the 10 most frequent ASCII words.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! `<count> <word>` per line, ordered by count descending, then word ascending.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;
const read_buffer_size = 64 * 1024;

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` should be printed before `b`.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

const Counter = struct {
    /// Owns the word keys stored in `counts`.
    arena: Allocator,
    gpa: Allocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Word currently being accumulated; may span multiple input chunks.
    pending: std.ArrayList(u8) = .empty,

    fn deinit(self: *Counter) void {
        self.counts.deinit(self.gpa);
        self.pending.deinit(self.gpa);
        self.* = undefined;
    }

    /// Tokenizes `chunk`, carrying any unterminated word over to the next call.
    fn feed(self: *Counter, chunk: []const u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) : (i += 1) {}
            if (i > start) try self.pending.appendSlice(self.gpa, chunk[start..i]);
            if (i == chunk.len) break; // word may continue in the next chunk
            try self.flush();
            while (i < chunk.len and !std.ascii.isAlphabetic(chunk[i])) : (i += 1) {}
        }
    }

    /// Records the pending word, if any.
    fn flush(self: *Counter) Allocator.Error!void {
        if (self.pending.items.len == 0) return;
        defer self.pending.clearRetainingCapacity();

        const word = self.pending.items;
        for (word) |*c| c.* = std.ascii.toLower(c.*);

        const gop = try self.counts.getOrPut(self.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = try self.arena.dupe(u8, word);
            gop.value_ptr.* = 1;
        }
    }

    /// Returns the best `top_n` entries in output order, stored in `out`.
    fn top(self: *const Counter, out: *[top_n]Entry) []Entry {
        var len: usize = 0;
        var it = self.counts.iterator();
        while (it.next()) |kv| {
            const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == top_n and !e.before(out[len - 1])) continue;
            // Insertion into a small sorted array; drops the last element when full.
            var pos = if (len < top_n) len else top_n - 1;
            while (pos > 0 and e.before(out[pos - 1])) : (pos -= 1) out[pos] = out[pos - 1];
            out[pos] = e;
            if (len < top_n) len += 1;
        }
        return out[0..len];
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();

    var counter: Counter = .{ .arena = arena_state.allocator(), .gpa = gpa };
    defer counter.deinit();

    var in_buf: [read_buffer_size]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &in_buf);
    const in = &stdin_reader.interface;

    while (true) {
        const chunk = in.buffered();
        if (chunk.len > 0) {
            try counter.feed(chunk);
            in.tossBuffered();
        }
        in.fillMore() catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdin_reader.err.?,
        };
    }
    try counter.flush();

    var top_buf: [top_n]Entry = undefined;
    const best = counter.top(&top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const out = &stdout_writer.interface;
    for (best) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    var counter: Counter = .{ .arena = arena_state.allocator(), .gpa = gpa };
    defer counter.deinit();

    // Feed one byte at a time to exercise words spanning chunk boundaries.
    for (0..input.len) |i| try counter.feed(input[i .. i + 1]);
    try counter.flush();

    var top_buf: [top_n]Entry = undefined;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    for (counter.top(&top_buf)) |e| try out.writer.print("{d} {s}\n", .{ e.count, e.word });
    try std.testing.expectEqualStrings(expected, out.written());
}

test "basic" {
    try expectTop("The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n");
}

test "separators" {
    try expectTop("don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n");
}

test "empty" {
    try expectTop("", "");
    try expectTop("123 \xff\xc3(", "");
}

test "top ten with ties" {
    try expectTop(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}
