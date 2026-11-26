//! `app wordfreq` — see the "wordfreq" section of SPEC.md.
//!
//! Input is streamed through the reader's buffer, so memory use is bounded by
//! the number of distinct words rather than by the size of the input. A word
//! that straddles two buffer fills is accumulated in a pending buffer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Number of words printed.
const top_n = 10;

/// Word frequencies: print the 10 most frequent words read from `in`.
///
/// `in` is standard input and `out` is buffered standard output; the caller
/// flushes `out` after this returns. `gpa` is a general-purpose allocator.
pub fn run(gpa: Allocator, in: *Io.Reader, out: *Io.Writer) !void {
    var counter: Counter = .init(gpa);
    defer counter.deinit();

    while (true) {
        const chunk = in.peekGreedy(1) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        try counter.feed(chunk);
        in.toss(chunk.len);
    }
    try counter.finish();

    var top: Top = .{};
    var it = counter.counts.iterator();
    while (it.next()) |entry| top.offer(.{ .word = entry.key_ptr.*, .count = entry.value_ptr.* });

    for (top.slice()) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
}

/// Counts lowercase words across a sequence of input chunks.
const Counter = struct {
    gpa: Allocator,
    /// Owns the bytes of every key in `counts`.
    arena: std.heap.ArenaAllocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// The lowercased prefix of a word that may continue in the next chunk.
    pending: std.ArrayList(u8) = .empty,

    fn init(gpa: Allocator) Counter {
        return .{ .gpa = gpa, .arena = .init(gpa) };
    }

    fn deinit(c: *Counter) void {
        c.pending.deinit(c.gpa);
        c.counts.deinit(c.gpa);
        c.arena.deinit();
        c.* = undefined;
    }

    /// Counts the words of `chunk`. A word running up to the end of `chunk` is
    /// held back until a later chunk (or `finish`) terminates it.
    fn feed(c: *Counter, chunk: []const u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!std.ascii.isAlphabetic(chunk[i])) {
                if (c.pending.items.len != 0) try c.flushPending();
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and std.ascii.isAlphabetic(chunk[i])) i += 1;
            const run_bytes = chunk[start..i];

            const dest = try c.pending.addManyAsSlice(c.gpa, run_bytes.len);
            for (dest, run_bytes) |*d, s| d.* = std.ascii.toLower(s);

            if (i < chunk.len) try c.flushPending();
        }
    }

    /// Counts the word still pending at end of input, if any.
    fn finish(c: *Counter) Allocator.Error!void {
        if (c.pending.items.len != 0) try c.flushPending();
    }

    fn flushPending(c: *Counter) Allocator.Error!void {
        const word = c.pending.items;
        const gop = try c.counts.getOrPut(c.gpa, word);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = c.arena.allocator().dupe(u8, word) catch |err| {
                c.counts.removeByPtr(gop.key_ptr);
                return err;
            };
            gop.value_ptr.* = 1;
        }
        c.pending.clearRetainingCapacity();
    }
};

const Entry = struct {
    word: []const u8,
    count: u64,

    /// Output order: count descending, then word ascending by byte value.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// The `top_n` best entries seen so far, kept sorted by `Entry.before`.
const Top = struct {
    buf: [top_n]Entry = undefined,
    len: usize = 0,

    fn offer(t: *Top, e: Entry) void {
        if (t.len == top_n and !e.before(t.buf[top_n - 1])) return;
        var i = @min(t.len, top_n - 1);
        while (i > 0 and e.before(t.buf[i - 1])) : (i -= 1) t.buf[i] = t.buf[i - 1];
        t.buf[i] = e;
        if (t.len < top_n) t.len += 1;
    }

    fn slice(t: *const Top) []const Entry {
        return t.buf[0..t.len];
    }
};

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var buf: [1024]u8 = undefined;
    var out: Io.Writer = .fixed(&buf);
    try run(std.testing.allocator, &in, &out);
    try std.testing.expectEqualStrings(expected, out.buffered());
}

test run {
    try expectOutput("", "");
    try expectOutput("123 _'- \x80\xff", "");
    try expectOutput("The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n");
    try expectOutput("Hello, hello! HELLO? world.\n", "3 hello\n1 world\n");
    try expectOutput("don't x1y caf\xc3\xa9", "1 caf\n1 don\n1 t\n1 x\n1 y\n");
    try expectOutput(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}

test "words spanning chunk boundaries" {
    var c: Counter = .init(std.testing.allocator);
    defer c.deinit();
    try c.feed("ab");
    try c.feed("CD e");
    try c.feed("f");
    try c.feed(" abcd");
    try c.finish();
    try std.testing.expectEqual(@as(?u64, 2), c.counts.get("abcd"));
    try std.testing.expectEqual(@as(?u64, 1), c.counts.get("ef"));
    try std.testing.expectEqual(@as(u32, 2), c.counts.count());
}
