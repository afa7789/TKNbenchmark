//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes command results to stdout. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("LruCache.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    // The cache borrows keys and values from this buffer, so it must outlive
    // the cache.
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    try run(gpa, input, out);
    try out.flush();
}

/// Executes every command in `input` and writes the results to `out`.
fn run(gpa: std.mem.Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    var cache: LruCache = try .init(gpa, parseCapacity(trimCr(first)));
    defer cache.deinit(gpa);

    while (lines.next()) |line| {
        try execute(gpa, &cache, trimCr(line), out);
    }
}

fn trimCr(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

/// Parses the leading decimal digits of the first token. A missing or
/// out-of-range number yields 0.
fn parseCapacity(line: []const u8) usize {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const token = tokens.next() orelse return 0;
    const digits = for (token, 0..) |c, i| {
        if (!std.ascii.isDigit(c)) break token[0..i];
    } else token;
    return std.fmt.parseUnsigned(usize, digits, 10) catch 0;
}

const Command = enum { SET, GET, DEL, SIZE };

fn execute(gpa: std.mem.Allocator, cache: *LruCache, line: []const u8, out: *Io.Writer) !void {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    // Blank or unrecognised lines produce no output.
    const name = tokens.next() orelse return;
    const command = std.meta.stringToEnum(Command, name) orelse return;
    switch (command) {
        .SET => {
            const key = tokens.next() orelse return;
            const value = tokens.next() orelse return;
            try cache.put(gpa, key, value);
        },
        .GET => {
            try out.writeAll(cache.get(tokens.next() orelse "") orelse "NULL");
            try out.writeByte('\n');
        },
        .DEL => try out.writeAll(if (cache.remove(tokens.next() orelse "")) "1\n" else "0\n"),
        .SIZE => try out.print("{d}\n", .{cache.count()}),
    }
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var buf: Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try run(std.testing.allocator, input, &buf.writer);
    try std.testing.expectEqualStrings(expected, buf.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "missing final newline, CRLF and junk lines" {
    try expectRun("1\r\nSET a 1\r\n\nFOO\nGET a\r\nDEL a", "1\n1\n");
}

test "parseCapacity" {
    try std.testing.expectEqual(5, parseCapacity(" 5x"));
    try std.testing.expectEqual(0, parseCapacity("-3"));
    try std.testing.expectEqual(0, parseCapacity(""));
    try std.testing.expectEqual(0, parseCapacity("99999999999999999999999"));
}

test {
    _ = LruCache;
}
