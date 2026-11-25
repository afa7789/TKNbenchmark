//! wordfreq: read stdin and print the 10 most frequent ASCII words.

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

/// Lowercases `text` in place and counts every maximal run of ASCII letters.
/// Keys in the returned map are slices of `text`.
fn countWords(gpa: std.mem.Allocator, text: []u8) !Counts {
    var counts: Counts = .empty;
    errdefer counts.deinit(gpa);

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
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
    }
    return counts;
}

/// Selects the highest-ranked entries into `buf`, returning them in rank order.
fn topEntries(counts: *const Counts, buf: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == buf.len and !e.before(buf[len - 1])) continue;
        // Insertion into the small sorted buffer, dropping the last if full.
        var pos = if (len < buf.len) len else len - 1;
        while (pos > 0 and e.before(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = e;
        if (len < buf.len) len += 1;
    }
    return buf[0..len];
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    var in_buf: [64 * 1024]u8 = undefined;
    var in: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const text = try in.interface.allocRemaining(arena, .unlimited);

    var counts = try countWords(arena, text);
    defer counts.deinit(arena);

    var top_buf: [top_n]Entry = undefined;
    const top = topEntries(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var out: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const stdout = &out.interface;
    for (top) |e| try stdout.print("{d} {s}\n", .{ e.count, e.word });
    try stdout.flush();
}

test "counts and ranks words" {
    const gpa = std.testing.allocator;
    var text = "The cat and the hat. don't stop_me 4now".*;
    var counts = try countWords(gpa, &text);
    defer counts.deinit(gpa);

    var buf: [3]Entry = undefined;
    const top = topEntries(&counts, &buf);
    try std.testing.expectEqual(@as(usize, 3), top.len);
    try std.testing.expectEqualStrings("the", top[0].word);
    try std.testing.expectEqual(@as(u32, 2), top[0].count);
    try std.testing.expectEqualStrings("and", top[1].word);
    try std.testing.expectEqualStrings("cat", top[2].word);
}

test "no words" {
    const gpa = std.testing.allocator;
    var text = "123 _'\xff".*;
    var counts = try countWords(gpa, &text);
    defer counts.deinit(gpa);
    var buf: [top_n]Entry = undefined;
    try std.testing.expectEqual(@as(usize, 0), topEntries(&counts, &buf).len);
}
