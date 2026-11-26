//! `app wordfreq`: see the "wordfreq" section of SPEC.md.
//!
//! Streams standard input through a `Counter`, then prints the `top_n` most
//! frequent words as `<count> <word>` lines.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Maximum number of lines printed.
pub const top_n = 10;

/// Runs the subcommand: reads standard input, writes standard output.
pub fn run(init: std.process.Init) !void {
    const io = init.io;

    var counter: Counter = .init(init.gpa);
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

    var top_buf: [top_n]Entry = undefined;
    const top = counter.top(&top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;
    writeEntries(out, top) catch |err| switch (err) {
        error.WriteFailed => return stdout.err.?,
    };
}

/// A word and the number of times it occurred.
pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Output order: count descending, then word ascending (byte order).
    pub fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Counts case-folded words over input supplied in arbitrary chunks; a word
/// may span chunk boundaries.
pub const Counter = struct {
    gpa: Allocator,
    /// Owns the bytes of every key in `counts`.
    words: std.heap.ArenaAllocator,
    counts: std.StringHashMapUnmanaged(u64) = .empty,
    /// Lowercased letters of the word currently being scanned.
    pending: std.ArrayList(u8) = .empty,

    pub fn init(gpa: Allocator) Counter {
        return .{ .gpa = gpa, .words = .init(gpa) };
    }

    pub fn deinit(c: *Counter) void {
        c.pending.deinit(c.gpa);
        c.counts.deinit(c.gpa);
        c.words.deinit();
        c.* = undefined;
    }

    /// Scans the next chunk of input.
    pub fn feed(c: *Counter, chunk: []const u8) Allocator.Error!void {
        var i: usize = 0;
        while (i < chunk.len) {
            if (!isLetter(chunk[i])) {
                if (c.pending.items.len != 0) try c.flush();
                i += 1;
                continue;
            }
            const start = i;
            while (i < chunk.len and isLetter(chunk[i])) i += 1;
            const dest = try c.pending.addManyAsSlice(c.gpa, i - start);
            for (dest, chunk[start..i]) |*d, s| d.* = s | 0x20;
        }
    }

    /// Ends the input, counting a word that runs up to its end.
    pub fn finish(c: *Counter) Allocator.Error!void {
        if (c.pending.items.len != 0) try c.flush();
    }

    fn flush(c: *Counter) Allocator.Error!void {
        const gop = try c.counts.getOrPut(c.gpa, c.pending.items);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.key_ptr.* = c.words.allocator().dupe(u8, c.pending.items) catch |err| {
                c.counts.removeByPtr(gop.key_ptr);
                return err;
            };
            gop.value_ptr.* = 1;
        }
        c.pending.clearRetainingCapacity();
    }

    /// Fills `buf` with the highest-ranked entries in output order and returns
    /// the filled prefix. The words are owned by the counter.
    pub fn top(c: *const Counter, buf: []Entry) []Entry {
        var len: usize = 0;
        var it = c.counts.iterator();
        while (it.next()) |kv| {
            const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
            if (len == buf.len and (len == 0 or !entry.ranksBefore(buf[len - 1]))) continue;
            // Insertion into the sorted prefix, dropping the last entry if full.
            var j = if (len < buf.len) len else len - 1;
            while (j > 0 and entry.ranksBefore(buf[j - 1])) : (j -= 1) buf[j] = buf[j - 1];
            buf[j] = entry;
            if (len < buf.len) len += 1;
        }
        return buf[0..len];
    }
};

fn isLetter(b: u8) bool {
    return (b | 0x20) -% 'a' < 26;
}

fn writeEntries(w: *Io.Writer, entries: []const Entry) Io.Writer.Error!void {
    for (entries) |e| try w.print("{d} {s}\n", .{ e.count, e.word });
    try w.flush();
}

const testing = std.testing;

fn expectTop(chunks: []const []const u8, expected: []const u8) !void {
    var counter: Counter = .init(testing.allocator);
    defer counter.deinit();
    for (chunks) |chunk| try counter.feed(chunk);
    try counter.finish();

    var top_buf: [top_n]Entry = undefined;
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeEntries(&out.writer, counter.top(&top_buf));
    try testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectTop(&.{"The cat and the hat."}, "2 the\n1 and\n1 cat\n1 hat\n");
}

test "no words" {
    try expectTop(&.{}, "");
    try expectTop(&.{"123 _' \xff\xfe.\n"}, "");
}

test "separators and case folding" {
    try expectTop(&.{"don't stop_me 4now, now-NOW \xc3\xa9Z@[`{"}, "3 now\n1 don\n1 me\n1 stop\n1 t\n1 z\n");
}

test "words spanning chunk boundaries" {
    try expectTop(&.{ "he", "", "LL", "o hel", "lo", " x", "y" }, "2 hello\n1 xy\n");
}

test "top 10 with ties" {
    try expectTop(
        &.{"zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha"},
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}

test "prefix ordering" {
    try expectTop(&.{"ab a abc a ab abc"}, "2 a\n2 ab\n2 abc\n");
}
