//! wordfreq: read stdin, print the 10 most frequent ASCII words (case-insensitive).

const std = @import("std");
const Io = std.Io;

const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u32,

    /// True if `a` ranks before `b`: higher count first, then word ascending.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

const Counts = std.StringHashMapUnmanaged(u32);

/// Lowercases every ASCII letter of `data` in place and counts each word.
/// Keys in `counts` are slices into `data`, so `data` must outlive `counts`.
fn countWords(gpa: std.mem.Allocator, data: []u8, counts: *Counts) !void {
    var i: usize = 0;
    while (i < data.len) {
        if (!std.ascii.isAlphabetic(data[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < data.len and std.ascii.isAlphabetic(data[i])) : (i += 1) {
            data[i] |= 0x20; // ASCII letters: setting bit 5 yields lowercase.
        }
        const gop = try counts.getOrPut(gpa, data[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
}

/// Returns the best `top_n` entries in rank order, stored in `buf`.
fn topEntries(counts: *const Counts, buf: *[top_n]Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == top_n and !e.before(buf[len - 1])) continue;
        // Insertion into the sorted, bounded buffer.
        var pos = if (len < top_n) len else top_n - 1;
        while (pos > 0 and e.before(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = e;
        if (len < top_n) len += 1;
    }
    return buf[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var in = Io.File.stdin().reader(io, &in_buf);
    const data = try in.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(data);

    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, data, &counts);

    var top_buf: [top_n]Entry = undefined;
    const top = topEntries(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var out = Io.File.stdout().writer(io, &out_buf);
    const stdout = &out.interface;
    for (top) |e| try stdout.print("{d} {s}\n", .{ e.count, e.word });
    try stdout.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const data = try gpa.dupe(u8, input);
    defer gpa.free(data);
    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, data, &counts);
    var buf: [top_n]Entry = undefined;
    const top = topEntries(&counts, &buf);
    try std.testing.expectEqual(expected.len, top.len);
    for (expected, top) |want, got| {
        try std.testing.expectEqualStrings(want.word, got.word);
        try std.testing.expectEqual(want.count, got.count);
    }
}

test "example" {
    try expectTop("The cat and the hat.", &.{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    });
}

test "separators and non-ascii bytes" {
    try expectTop("don't\xffstop_me 4now, now-NOW\xc3\xa9", &.{
        .{ .word = "now", .count = 3 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    });
}

test "empty and wordless input" {
    try expectTop("", &.{});
    try expectTop("123 _'@[`{\x80", &.{});
}
