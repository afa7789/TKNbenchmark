//! Word frequencies: prints the ten most frequent ASCII-letter words, case-folded.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const top_n = 10;

pub const Entry = struct {
    word: []const u8,
    count: u64,

    /// True when `a` ranks before `b`: higher count first, then word ascending.
    fn before(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

/// Counts the words in `input` and writes the top entries to `out`.
/// `input` is lowercased in place; the counted words are slices into it.
pub fn run(gpa: Allocator, input: []u8, out: *std.Io.Writer) !void {
    var counts: std.StringHashMapUnmanaged(u64) = .empty;
    defer counts.deinit(gpa);
    try countWords(gpa, input, &counts);

    var top: [top_n]Entry = undefined;
    for (topEntries(&counts, &top)) |entry| {
        try out.print("{d} {s}\n", .{ entry.count, entry.word });
    }
}

fn isLetter(c: u8) bool {
    return (c | 0x20) -% 'a' < 26;
}

fn countWords(gpa: Allocator, input: []u8, counts: *std.StringHashMapUnmanaged(u64)) !void {
    var i: usize = 0;
    while (i < input.len) {
        if (!isLetter(input[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < input.len and isLetter(input[i])) : (i += 1) {
            input[i] |= 0x20;
        }
        const gop = try counts.getOrPut(gpa, input[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }
}

/// Selects the best-ranked entries into `buf`, returning them in rank order.
fn topEntries(counts: *const std.StringHashMapUnmanaged(u64), buf: *[top_n]Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const entry: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == top_n and !entry.before(buf[len - 1])) continue;
        // Insertion into the small sorted buffer, dropping the last entry when full.
        var pos = if (len == top_n) len - 1 else len;
        while (pos > 0 and entry.before(buf[pos - 1])) : (pos -= 1) {
            buf[pos] = buf[pos - 1];
        }
        buf[pos] = entry;
        if (len < top_n) len += 1;
    }
    return buf[0..len];
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    const copy = try gpa.dupe(u8, input);
    defer gpa.free(copy);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, copy, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n");
}

test "separators and folding" {
    try expectOutput("don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n");
    try expectOutput("\xffAb\xc3(aB", "2 ab\n");
}

test "empty input" {
    try expectOutput("", "");
    try expectOutput("123 ... \xff", "");
}

test "top ten with ties" {
    try expectOutput(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}
