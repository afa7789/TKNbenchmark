//! wordfreq: print the 10 most frequent ASCII words read from standard input.
//!
//! A word is a maximal run of ASCII letters; every other byte is a separator.
//! Words are folded to lowercase. Output is `<count> <word>` per line, ordered
//! by count descending and then by word ascending (byte order).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u64,

    /// True when `a` ranks strictly before `b` in the output order.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

const Counts = std.StringHashMapUnmanaged(u64);

/// Lowercases `text` in place and counts each word. Keys of the returned map
/// borrow from `text`, which must outlive the map.
fn countWords(gpa: Allocator, text: []u8) Allocator.Error!Counts {
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
            text[i] |= 0x20; // ASCII letters: setting bit 5 yields lowercase.
        }
        const gop = try counts.getOrPut(gpa, text[start..i]);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
    }
    return counts;
}

/// Selects the `top.len` highest-ranked entries into `top`, sorted in output
/// order. Returns the populated prefix.
fn selectTop(counts: *const Counts, top: []Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == top.len and !entry.before(top[len - 1])) continue;

        // Insertion into the small sorted buffer, dropping the last if full.
        var pos = if (len < top.len) len else len - 1;
        while (pos > 0 and entry.before(top[pos - 1])) : (pos -= 1) {
            top[pos] = top[pos - 1];
        }
        top[pos] = entry;
        if (len < top.len) len += 1;
    }
    return top[0..len];
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const text = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(text);

    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);

    var top_buf: [top_n]Entry = undefined;
    const top = selectTop(&counts, &top_buf);

    var out_buf: [4096]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;
    for (top) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
    try out.flush();
}

fn expectTop(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    const text = try gpa.dupe(u8, input);
    defer gpa.free(text);
    var counts = try countWords(gpa, text);
    defer counts.deinit(gpa);
    var top_buf: [top_n]Entry = undefined;

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    for (selectTop(&counts, &top_buf)) |e| try out.writer.print("{d} {s}\n", .{ e.count, e.word });
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectTop("The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n");
}

test "separators and high bytes" {
    try expectTop("don't stop_me 4now, now-NOW\xff\xc3(now", "4 now\n1 don\n1 me\n1 stop\n1 t\n");
}

test "empty input" {
    try expectTop("", "");
    try expectTop("123 ... \x80\xff", "");
}

test "limits to ten, ties by word" {
    try expectTop(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}
