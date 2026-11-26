//! Word frequency counter: prints the ten most frequent ASCII-letter words.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const top_n = 10;

const Entry = struct {
    word: []const u8,
    count: u64,

    /// Count descending, then word ascending (byte order).
    fn before(_: void, a: Entry, b: Entry) bool {
        if (a.count != b.count) return a.count > b.count;
        return std.mem.order(u8, a.word, b.word) == .lt;
    }
};

/// Counts words in `input` and writes the top entries to `out`.
/// `input` is lowercased in place so that map keys can borrow from it.
pub fn run(gpa: Allocator, input: []u8, out: *std.Io.Writer) !void {
    var counts: std.StringHashMapUnmanaged(u64) = .empty;
    defer counts.deinit(gpa);

    var i: usize = 0;
    while (i < input.len) {
        if (!std.ascii.isAlphabetic(input[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < input.len and std.ascii.isAlphabetic(input[i])) : (i += 1) {
            input[i] = std.ascii.toLower(input[i]);
        }
        const gop = try counts.getOrPut(gpa, input[start..i]);
        if (gop.found_existing) gop.value_ptr.* += 1 else gop.value_ptr.* = 1;
    }

    var top: [top_n]Entry = undefined;
    const n = selectTop(&counts, &top);
    for (top[0..n]) |e| try out.print("{d} {s}\n", .{ e.count, e.word });
}

/// Keeps the best `top.len` entries in sorted order via insertion; O(distinct * top_n).
fn selectTop(counts: *const std.StringHashMapUnmanaged(u64), top: []Entry) usize {
    var n: usize = 0;
    var it = counts.iterator();
    while (it.next()) |kv| {
        const e: Entry = .{ .word = kv.key_ptr.*, .count = kv.value_ptr.* };
        if (n == top.len and !Entry.before({}, e, top[n - 1])) continue;
        var pos = if (n < top.len) n else top.len - 1;
        if (n < top.len) n += 1;
        while (pos > 0 and Entry.before({}, e, top[pos - 1])) : (pos -= 1) top[pos] = top[pos - 1];
        top[pos] = e;
    }
    return n;
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

test "separators and empty" {
    try expectOutput("don't stop_me 4now, now-NOW", "3 now\n1 don\n1 me\n1 stop\n1 t\n");
    try expectOutput("", "");
    try expectOutput("123 \xff\xc3(", "");
}

test "top ten with ties" {
    try expectOutput(
        "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
        "2 alpha\n1 beta\n1 eta\n1 iota\n1 kappa\n1 lambda\n1 mu\n1 nu\n1 omicron\n1 pi\n",
    );
}
