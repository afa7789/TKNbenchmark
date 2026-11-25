//! wordfreq: print the 10 most frequent ASCII-letter words read from stdin.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// Ordering for the output: higher count first, then word ascending.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

pub const Counts = std.StringHashMapUnmanaged(u64);

/// Lowercases ASCII letters in `text` in place and counts each word.
/// Keys in `counts` are slices into `text`, which must outlive the map.
pub fn countWords(gpa: Allocator, text: []u8, counts: *Counts) Allocator.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        if (!std.ascii.isAlphabetic(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {
            text[i] = std.ascii.toLower(text[i]);
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
}

/// Selects the `top_n` best entries into `buf`, returning the sorted prefix.
pub fn topWords(counts: *const Counts, buf: *[top_n]Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == top_n and !e.before(buf[len - 1])) continue;
        // Insertion into the sorted bounded buffer.
        var j: usize = if (len < top_n) len else top_n - 1;
        while (j > 0 and e.before(buf[j - 1])) : (j -= 1) buf[j] = buf[j - 1];
        buf[j] = e;
        if (len < top_n) len += 1;
    }
    return buf[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var in: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const text = try in.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, text, &counts);

    var top_buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var out: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const stdout = &out.interface;
    for (top) |e| try stdout.print("{d} {s}\n", .{ e.count, e.word });
    try stdout.flush();
}

fn expectTop(input: []const u8, expected: []const Entry) !void {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, input);
    defer gpa.free(text);
    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, text, &counts);
    var buf: [top_n]Entry = undefined;
    const top = topWords(&counts, &buf);
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
    try expectTop("don't stop_me 4now, now-NOW\xffnow\xc3\xa9", &.{
        .{ .word = "now", .count = 4 },
        .{ .word = "don", .count = 1 },
        .{ .word = "me", .count = 1 },
        .{ .word = "stop", .count = 1 },
        .{ .word = "t", .count = 1 },
    });
}

test "empty" {
    try expectTop("123 ... \x80", &.{});
}
