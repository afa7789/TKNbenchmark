//! wordfreq: print the 10 most frequent ASCII words read from standard input.

const std = @import("std");
const Io = std.Io;

const max_input_bytes = 1 << 30;
const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u32,

    /// Ordering for output: count descending, then word ascending (byte order).
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

const Counts = std.StringHashMapUnmanaged(u32);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(gpa, .limited(max_input_bytes));
    defer gpa.free(input);

    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, input, &counts);

    var top_buf: [top_n]Entry = undefined;
    const top = selectTop(&counts, &top_buf);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;
    for (top) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    try out.flush();
}

/// Lowercases `input` in place and tallies every maximal run of ASCII letters.
/// Map keys are slices into `input`, so it must outlive `counts`.
fn countWords(gpa: std.mem.Allocator, input: []u8, counts: *Counts) !void {
    var i: usize = 0;
    while (i < input.len) {
        if (!std.ascii.isAlphabetic(input[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {
            input[i] |= 0x20; // ASCII letters: setting bit 5 lowercases.
        }
        const gop = try counts.getOrPut(gpa, input[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
}

/// Returns up to `buf.len` entries with the highest rank, sorted for output.
fn selectTop(counts: *const Counts, buf: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buf.len and !e.before(buf[len - 1])) continue;
        // Insertion into a small sorted array; drops the last entry when full.
        var pos = if (len < buf.len) len else len - 1;
        while (pos > 0 and e.before(buf[pos - 1])) : (pos -= 1) buf[pos] = buf[pos - 1];
        buf[pos] = e;
        if (len < buf.len) len += 1;
    }
    return buf[0..len];
}

fn runCount(input: []const u8, buf: []Entry) ![]Entry {
    const copy = try std.testing.allocator.dupe(u8, input);
    defer std.testing.allocator.free(copy);
    var counts: Counts = .empty;
    defer counts.deinit(std.testing.allocator);
    try countWords(std.testing.allocator, copy, &counts);
    const top = selectTop(&counts, buf);
    // Detach words from the freed copy for assertions.
    for (top) |*e| e.word = try std.testing.allocator.dupe(u8, e.word);
    return top;
}

test "counts, folds case, orders ties by word" {
    var buf: [top_n]Entry = undefined;
    const top = try runCount("The cat and the hat.\xffdon't", &buf);
    defer for (top) |e| std.testing.allocator.free(e.word);
    const want = [_]Entry{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "don", .count = 1 },
        .{ .word = "hat", .count = 1 },
        .{ .word = "t", .count = 1 },
    };
    try std.testing.expectEqual(want.len, top.len);
    for (want, top) |w, g| {
        try std.testing.expectEqual(w.count, g.count);
        try std.testing.expectEqualStrings(w.word, g.word);
    }
}

test "empty input yields nothing" {
    var buf: [top_n]Entry = undefined;
    const top = try runCount("123 _' \x80", &buf);
    try std.testing.expectEqual(@as(usize, 0), top.len);
}
