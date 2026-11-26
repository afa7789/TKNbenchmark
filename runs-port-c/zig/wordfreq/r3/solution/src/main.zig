//! wordfreq: read stdin, print the 10 most frequent ASCII-letter words.
//!
//! A word is a maximal run of [A-Za-z], folded to lowercase. Output is
//! "<count> <word>" ordered by count descending, then word ascending.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

/// Maps each distinct lowercase word to its number of occurrences.
/// Keys borrow from the input buffer, which must outlive the map.
const Counts = std.StringHashMapUnmanaged(u64);

const Ranked = struct {
    word: []const u8,
    count: u64,

    /// True if `a` should be printed before `b`.
    fn before(a: Ranked, b: Ranked) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

fn isLetter(c: u8) bool {
    return (c | 0x20) -% 'a' < 26;
}

/// Lowercases every word in `text` in place and counts occurrences.
fn countWords(gpa: Allocator, text: []u8) Allocator.Error!Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

    var i: usize = 0;
    while (i < text.len) {
        if (!isLetter(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and isLetter(text[i])) : (i += 1) {
            text[i] |= 0x20;
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
    }
    return counts;
}

/// Selects the highest-ranked words into `out` (sorted), returning how many were filled.
fn selectTop(counts: *const Counts, out: []Ranked) []Ranked {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const item: Ranked = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == out.len and !item.before(out[len - 1])) continue;

        var j = if (len < out.len) blk: {
            len += 1;
            break :blk len - 1;
        } else out.len - 1;
        while (j > 0 and item.before(out[j - 1])) : (j -= 1) {
            out[j] = out[j - 1];
        }
        out[j] = item;
    }
    return out[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var read_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &read_buf);
    const text = stdin_reader.interface.allocRemaining(gpa, .unlimited) catch |err| switch (err) {
        error.ReadFailed => return stdin_reader.err.?,
        else => |e| return e,
    };
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Ranked = undefined;
    const top = selectTop(&counts, &top_buf);

    var write_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &write_buf);
    const out = &stdout_writer.interface;
    for (top) |r| {
        try out.print("{d} {s}\n", .{ r.count, r.word });
    }
    try out.flush();
}

test "counts words case-insensitively and ranks ties by word" {
    const gpa = std.testing.allocator;
    var text = "The cat and the hat.".*;
    var counts = try countWords(gpa, &text);
    defer counts.deinit(gpa);

    var buf: [top_n]Ranked = undefined;
    const top = selectTop(&counts, &buf);
    try std.testing.expectEqual(@as(usize, 4), top.len);
    try std.testing.expectEqualStrings("the", top[0].word);
    try std.testing.expectEqual(@as(u64, 2), top[0].count);
    try std.testing.expectEqualStrings("and", top[1].word);
    try std.testing.expectEqualStrings("cat", top[2].word);
    try std.testing.expectEqualStrings("hat", top[3].word);
}

test "non-letters separate words" {
    const gpa = std.testing.allocator;
    var text = "don't stop_me 4now, now-NOW\xff\xc3(x".*;
    var counts = try countWords(gpa, &text);
    defer counts.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 3), counts.get("now"));
    try std.testing.expectEqual(@as(?u64, 1), counts.get("t"));
    try std.testing.expectEqual(@as(?u64, 1), counts.get("x"));
    try std.testing.expectEqual(@as(u32, 6), counts.count());
}
