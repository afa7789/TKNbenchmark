//! Simulates an LRU cache driven by commands read from standard input.
//! See SPEC.md for the input format and command semantics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Lru = @import("Lru.zig");

/// ASCII whitespace as understood by Python's `bytes.split()` and `int()`.
const whitespace = " \t\n\r\x0b\x0c";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &.{});
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try run(gpa, input, out);
    try out.flush();
}

/// Executes every command in `input`, writing one line per output to `out`.
/// Keys and values in the cache borrow from `input`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(lines.first()) orelse return;

    var cache: Lru = .init(capacity);
    defer cache.deinit(gpa);
    // Never more entries than SET commands, so bound the reservation by the line count.
    try cache.ensureTotalCapacity(gpa, @min(capacity, std.mem.count(u8, input, "\n")) + 1);

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, whitespace);
        const cmd = tokens.next() orelse continue;
        switch (Command.parse(cmd) orelse continue) {
            .get => {
                const key = tokens.next() orelse continue;
                try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
            },
            .set => {
                const key = tokens.next() orelse continue;
                const value = tokens.next() orelse continue;
                try cache.put(gpa, key, value);
            },
            .del => {
                const key = tokens.next() orelse continue;
                try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
            },
            .size => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

const Command = enum {
    get,
    set,
    del,
    size,

    const map: std.StaticStringMap(Command) = .initComptime(.{
        .{ "GET", .get },
        .{ "SET", .set },
        .{ "DEL", .del },
        .{ "SIZE", .size },
    });

    fn parse(token: []const u8) ?Command {
        return map.get(token);
    }
};

/// Parses the capacity line with Python `int()` rules: surrounding whitespace,
/// an optional sign, and single underscores between digits are accepted.
/// Negative values clamp to 0 and oversized values saturate. Returns null if
/// the line is not an integer.
fn parseCapacity(line: []const u8) ?usize {
    var digits = std.mem.trim(u8, line, whitespace);
    var negative = false;
    if (digits.len > 0 and (digits[0] == '+' or digits[0] == '-')) {
        negative = digits[0] == '-';
        digits = digits[1..];
    }
    if (digits.len == 0) return null;

    var value: usize = 0;
    var prev_digit = false;
    for (digits) |c| switch (c) {
        '0'...'9' => {
            value = std.math.mul(usize, value, 10) catch std.math.maxInt(usize);
            value = std.math.add(usize, value, c - '0') catch std.math.maxInt(usize);
            prev_digit = true;
        },
        '_' => {
            if (!prev_digit) return null;
            prev_digit = false;
        },
        else => return null,
    };
    if (!prev_digit) return null;
    return if (negative) 0 else value;
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try run(std.testing.allocator, input, &buf.writer);
    try std.testing.expectEqualStrings(expected, buf.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "del and size without trailing newline" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "blank lines, CRLF and unknown commands are ignored" {
    try expectOutput("1\r\n\nSET a 1\r\nNOPE\n  \nGET a\r\n", "1\n");
}

test "invalid capacity produces no output" {
    try expectOutput("x\nSIZE\n", "");
    try expectOutput("", "");
}

test "parseCapacity follows Python int()" {
    try std.testing.expectEqual(5, parseCapacity(" +5 \r"));
    try std.testing.expectEqual(1000, parseCapacity("1_000"));
    try std.testing.expectEqual(0, parseCapacity("-3"));
    try std.testing.expectEqual(null, parseCapacity("1__0"));
    try std.testing.expectEqual(null, parseCapacity("_1"));
    try std.testing.expectEqual(null, parseCapacity("1_"));
    try std.testing.expectEqual(null, parseCapacity("-"));
    try std.testing.expectEqual(std.math.maxInt(usize), parseCapacity("99999999999999999999999"));
}

test {
    _ = Lru;
}
