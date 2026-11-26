//! LRU cache simulator: reads a capacity and a list of commands from stdin
//! and writes one line per GET, DEL and SIZE command to stdout (see SPEC.md).

const std = @import("std");
const LruCache = @import("lru.zig").LruCache;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buf: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buf);
    // Keys and values stored in the cache borrow from this buffer.
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buf);
    const out = &stdout_writer.interface;

    try run(gpa, input, out);
    try out.flush();
}

/// Executes the program text in `input`, writing results to `out`.
pub fn run(gpa: std.mem.Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = try parseCapacity(lines.first());

    var cache: LruCache = .init(capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;

        var tokens = std.mem.splitScalar(u8, line, ' ');
        const command = tokens.first();
        if (std.mem.eql(u8, command, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.rest();
            try cache.put(gpa, key, value);
        } else if (std.mem.eql(u8, command, "GET")) {
            try out.print("{s}\n", .{cache.get(tokens.rest()) orelse "NULL"});
        } else if (std.mem.eql(u8, command, "DEL")) {
            try out.writeAll(if (cache.remove(tokens.rest())) "1\n" else "0\n");
        } else if (std.mem.eql(u8, command, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
        // Unknown commands are ignored.
    }
}

fn parseCapacity(line: []const u8) !u32 {
    const text = std.mem.trim(u8, line, " \t\r");
    const capacity = std.fmt.parseInt(u32, text, 10) catch return error.InvalidCapacity;
    if (capacity < 1 or capacity > LruCache.max_capacity) return error.InvalidCapacity;
    return capacity;
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try run(std.testing.allocator, input, &buf.writer);
    try std.testing.expectEqualStrings(expected, buf.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "missing final newline and CRLF" {
    try expectRun("3\r\nSET x 1\r\nDEL x\r\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test {
    _ = @import("lru.zig");
}
