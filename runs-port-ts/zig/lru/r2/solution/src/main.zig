//! Reads an LRU cache capacity followed by SET/GET/DEL/SIZE commands from
//! standard input and writes the command results to standard output.

const std = @import("std");
const Allocator = std.mem.Allocator;
const LruCache = @import("lru.zig").LruCache;

const Command = enum { SET, GET, DEL, SIZE };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    // The input stays alive for the whole run: the cache borrows keys and
    // values straight out of it.
    const input = try stdin_reader.interface.allocRemaining(init.arena.allocator(), .unlimited);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try run(init.gpa, input, out);
    try out.flush();
}

fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(lines.first()) orelse return;

    var cache: LruCache = .init(capacity);
    defer cache.deinit(gpa);
    try cache.reserve(gpa, std.mem.count(u8, input, "\n"));

    while (lines.next()) |raw| {
        const line = if (std.mem.endsWith(u8, raw, "\r")) raw[0 .. raw.len - 1] else raw;
        if (line.len == 0) continue;

        const sp1 = std.mem.indexOfScalar(u8, line, ' ');
        const name = line[0 .. sp1 orelse line.len];
        // Unknown commands are ignored.
        const command = std.meta.stringToEnum(Command, name) orelse continue;
        switch (command) {
            .SET => {
                const key_start = (sp1 orelse continue) + 1;
                const sp2 = std.mem.indexOfScalarPos(u8, line, key_start, ' ') orelse continue;
                try cache.put(gpa, line[key_start..sp2], line[sp2 + 1 ..]);
            },
            .GET => {
                const key = line[(sp1 orelse continue) + 1 ..];
                try out.writeAll(cache.get(key) orelse "NULL");
                try out.writeByte('\n');
            },
            .DEL => {
                const key = line[(sp1 orelse continue) + 1 ..];
                try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
            },
            .SIZE => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

/// Parses the capacity line leniently, like JavaScript's `parseInt(s, 10)`:
/// leading whitespace and a sign are accepted and trailing garbage is
/// ignored. Returns null unless the result is a positive integer.
fn parseCapacity(line: []const u8) ?usize {
    var rest = std.mem.trimStart(u8, line, " \t\r\n\x0b\x0c\xa0");
    var negative = false;
    if (rest.len > 0 and (rest[0] == '+' or rest[0] == '-')) {
        negative = rest[0] == '-';
        rest = rest[1..];
    }

    var value: usize = 0;
    var digits: usize = 0;
    for (rest) |c| {
        if (!std.ascii.isDigit(c)) break;
        value = std.math.mul(usize, value, 10) catch std.math.maxInt(usize);
        value +|= c - '0';
        digits += 1;
    }
    if (digits == 0 or negative or value == 0) return null;
    return value;
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "lenient parsing" {
    try expectRun("  +2xyz\r\nSET a 1 2\r\n\nGET a\nGET\nBOGUS\nSIZE 9\n", "1 2\n1\n");
    try expectRun("0\nSIZE\n", "");
    try expectRun("-3\nSIZE\n", "");
    try expectRun("", "");
}

test "parseCapacity" {
    try std.testing.expectEqual(1_000_000, parseCapacity("1000000"));
    try std.testing.expectEqual(12, parseCapacity("\xa012.5"));
    try std.testing.expectEqual(null, parseCapacity("abc"));
    try std.testing.expectEqual(null, parseCapacity("-0"));
}

test {
    _ = @import("lru.zig");
}
