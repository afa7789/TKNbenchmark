//! Simulates an LRU cache driven by commands read from standard input.
//!
//! Line 1 holds the capacity; every later line is one of
//! `SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const LruCache = @import("LruCache.zig");

/// Characters treated as token separators (matches Python's `bytes.split()`).
const whitespace = " \t\r\x0b\x0c";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try run(gpa, input, out);
    try out.flush();
}

pub const RunError = Allocator.Error || std.Io.Writer.Error || error{InvalidCapacity};

/// Executes the command stream in `input`, writing one line per output to `out`.
/// `input` must outlive the call; keys and values are borrowed from it.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) RunError!void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const header = std.mem.trim(u8, lines.first(), whitespace ++ "\n");
    if (header.len == 0) return;

    const capacity = std.fmt.parseInt(i64, header, 10) catch return error.InvalidCapacity;
    var cache: LruCache = .init(std.math.cast(usize, capacity) orelse 0);
    defer cache.deinit(gpa);

    // Live entries never exceed capacity + 1, nor the number of commands.
    const commands = std.mem.countScalar(u8, input, '\n') + 1;
    try cache.ensureTotalCapacity(gpa, @min(cache.capacity, commands) + 1);

    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, whitespace);
        const command = tokens.next() orelse continue;
        const Command = enum { GET, SET, DEL, SIZE };
        const cmd = std.meta.stringToEnum(Command, command) orelse continue;
        switch (cmd) {
            .GET => {
                const key = tokens.next() orelse continue;
                try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
            },
            .SET => {
                const key = tokens.next() orelse continue;
                const value = tokens.next() orelse continue;
                try cache.put(gpa, key, value);
            },
            .DEL => {
                const key = tokens.next() orelse continue;
                try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
            },
            .SIZE => try out.print("{d}\n", .{cache.len()}),
        }
    }
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

test "blank lines, CRLF and missing trailing newline" {
    try expectRun("1\r\n\nSET a 1\r\nGET a\r\n\nSIZE", "1\n1\n");
}

test "empty input" {
    try expectRun("", "");
    try expectRun("  \n", "");
}

test {
    _ = LruCache;
}
