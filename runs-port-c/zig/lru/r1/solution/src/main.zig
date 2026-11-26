//! LRU cache simulator driven by commands on standard input (see SPEC.md).
//!
//! The whole input is read into memory up front; the cache stores slices
//! into that buffer, so keys and values are never copied.

const std = @import("std");
const Io = std.Io;
const Lru = @import("Lru.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(trimCr(lines.first())) orelse return; // nothing to simulate

    // Every live key needs its own SET line, which bounds the pool size.
    const max_entries = std.mem.countScalar(u8, input, '\n') + 1;
    var cache = Lru.init(gpa, capacity, max_entries) catch |err| switch (err) {
        error.ZeroCapacity => unreachable, // rejected by parseCapacity
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer cache.deinit(gpa);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    while (lines.next()) |line| try runCommand(&cache, trimCr(line), out);
    try out.flush();
}

fn trimCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

/// Parse the first token of the header line as a positive decimal integer.
fn parseCapacity(line: []const u8) ?usize {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const tok = tokens.next() orelse return null;
    if (tok.len > 18) return null;
    var value: usize = 0;
    for (tok) |c| {
        if (!std.ascii.isDigit(c)) return null;
        value = value * 10 + (c - '0');
    }
    return if (value == 0) null else value;
}

const Command = enum { GET, SET, DEL, SIZE };

/// Execute one command line. Blank lines, unknown commands and commands
/// with missing operands are ignored.
fn runCommand(cache: *Lru, line: []const u8, out: *Io.Writer) Io.Writer.Error!void {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const name = tokens.next() orelse return;
    const command = std.meta.stringToEnum(Command, name) orelse return;

    switch (command) {
        .GET => {
            const key = tokens.next() orelse return;
            try out.writeAll(cache.get(key) orelse "NULL");
            try out.writeByte('\n');
        },
        .SET => {
            const key = tokens.next() orelse return;
            const value = tokens.next() orelse return;
            cache.put(key, value);
        },
        .DEL => {
            const key = tokens.next() orelse return;
            try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
        },
        .SIZE => try out.print("{d}\n", .{cache.count()}),
    }
}

test parseCapacity {
    try std.testing.expectEqual(2, parseCapacity("2"));
    try std.testing.expectEqual(5, parseCapacity("  5 extra"));
    try std.testing.expectEqual(null, parseCapacity("0"));
    try std.testing.expectEqual(null, parseCapacity("1x"));
    try std.testing.expectEqual(null, parseCapacity(""));
    try std.testing.expectEqual(null, parseCapacity("1234567890123456789"));
}

test {
    _ = Lru;
}
