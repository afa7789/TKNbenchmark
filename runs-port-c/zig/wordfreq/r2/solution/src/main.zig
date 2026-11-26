//! wordfreq: read stdin, print the 10 most frequent ASCII words.
//!
//! A word is a maximal run of ASCII letters, folded to lowercase. Output is
//! "<count> <word>" per line, ordered by count descending, then word ascending
//! (byte order), at most `top_n` lines.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

/// Word -> occurrence count. Keys borrow from the input buffer.
const Counts = std.StringHashMapUnmanaged(u64);

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True if `a` ranks before `b`: higher count, then smaller word in byte order.
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

/// Fixed-capacity, best-first list of the highest-ranked entries seen so far.
const TopList = struct {
    items: [top_n]Entry = undefined,
    len: usize = 0,

    fn offer(self: *TopList, e: Entry) void {
        if (self.len == top_n and !e.ranksBefore(self.items[top_n - 1])) return;
        var pos = if (self.len < top_n) blk: {
            self.len += 1;
            break :blk self.len - 1;
        } else top_n - 1;
        while (pos > 0 and e.ranksBefore(self.items[pos - 1])) : (pos -= 1) {
            self.items[pos] = self.items[pos - 1];
        }
        self.items[pos] = e;
    }

    fn slice(self: *const TopList) []const Entry {
        return self.items[0..self.len];
    }
};

/// Lowercases every word in `text` in place and counts it in `counts`.
/// Map keys are slices of `text`, so `text` must outlive `counts`.
fn countWords(gpa: Allocator, counts: *Counts, text: []u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        while (i < text.len and !std.ascii.isAlphabetic(text[i])) i += 1;
        const start = i;
        while (i < text.len and std.ascii.isAlphabetic(text[i])) : (i += 1) {
            text[i] |= 0x20; // ASCII letter -> lowercase
        }
        if (i == start) break;
        const gop = try counts.getOrPut(gpa, text[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
}

fn selectTop(counts: *const Counts) TopList {
    var top: TopList = .{};
    var it = counts.iterator();
    while (it.next()) |kv| top.offer(.{ .word = kv.key_ptr.*, .count = kv.value_ptr.* });
    return top;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var read_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &read_buf);
    const text = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, &counts, text);

    const top = selectTop(&counts);

    var write_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &write_buf);
    const out = &stdout_writer.interface;
    for (top.slice()) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    try out.flush();
}

test "counts and ranks words" {
    const gpa = std.testing.allocator;
    var text = "The cat and the hat.".*;
    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, &counts, &text);

    const top = selectTop(&counts);
    const want = [_]Entry{
        .{ .word = "the", .count = 2 },
        .{ .word = "and", .count = 1 },
        .{ .word = "cat", .count = 1 },
        .{ .word = "hat", .count = 1 },
    };
    try std.testing.expectEqual(want.len, top.len);
    for (want, top.slice()) |w, g| {
        try std.testing.expectEqualStrings(w.word, g.word);
        try std.testing.expectEqual(w.count, g.count);
    }
}

test "non-letters separate words" {
    const gpa = std.testing.allocator;
    var text = "don't stop_me 4now, now-NOW\xff\xc3(now".*;
    var counts: Counts = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, &counts, &text);
    try std.testing.expectEqual(@as(u64, 4), counts.get("now").?);
    try std.testing.expectEqual(@as(u64, 1), counts.get("t").?);
    try std.testing.expectEqual(@as(usize, 5), counts.count());
}
