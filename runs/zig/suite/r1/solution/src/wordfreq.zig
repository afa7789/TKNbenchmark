//! `wordfreq`: print the ten most frequent ASCII-letter words of the input.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u32,

    /// True when `a` ranks strictly before `b`: higher count first, then byte order.
    fn ranksBefore(a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.lessThan(u8, a.word, b.word);
    }
};

/// Counts words in `input` and writes the top entries to `out`.
/// `input` is lowercased in place so that map keys can borrow from it.
pub fn run(gpa: Allocator, input: []u8, out: *std.Io.Writer) !void {
    var counts: std.StringHashMapUnmanaged(u32) = .empty;
    defer counts.deinit(gpa);

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
        gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
    }

    var top: [top_n]Entry = undefined;
    const ranked = selectTop(&counts, &top);
    for (ranked) |entry| try out.print("{d} {s}\n", .{ entry.count, entry.word });
}

/// Fills `top` with the best-ranked entries, in rank order, and returns the used prefix.
fn selectTop(counts: *const std.StringHashMapUnmanaged(u32), top: *[top_n]Entry) []Entry {
    var len: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const candidate: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (len == top_n and !candidate.ranksBefore(top[len - 1])) continue;
        // Insertion into the small sorted array, dropping the last entry if full.
        var pos = if (len < top_n) len else top_n - 1;
        while (pos > 0 and candidate.ranksBefore(top[pos - 1])) : (pos -= 1) {
            top[pos] = top[pos - 1];
        }
        top[pos] = candidate;
        if (len < top_n) len += 1;
    }
    return top[0..len];
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    const buf = try gpa.dupe(u8, input);
    defer gpa.free(buf);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, buf, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("The cat and the hat.", "2 the\n1 and\n1 cat\n1 hat\n");
}

test "separators and empty input" {
    try expectOutput("don't stop_me 4now, now-NOW\xff", "3 now\n1 don\n1 me\n1 stop\n1 t\n");
    try expectOutput("", "");
    try expectOutput("123 \xc3\xa9 !!", "");
}

test "at most ten lines, ties by word" {
    try expectOutput(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}
