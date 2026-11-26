//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes one line of output per GET, DEL and SIZE command.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("LruCache.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    // The cache borrows keys and values from this buffer, so it must outlive it.
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try run(gpa, input, out);
    try out.flush();
}

const Command = enum { SET, GET, DEL, SIZE };

/// Executes the program described by `input`, writing results to `out`.
/// Keys and values stored in the cache are slices of `input`.
fn run(gpa: std.mem.Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = LineIterator{ .rest = input };
    const first = lines.next() orelse return;

    var cache: LruCache = .init(parseCapacity(first));
    defer cache.deinit(gpa);

    while (lines.next()) |line| {
        var tokens = std.mem.splitScalar(u8, line, ' ');
        const command = std.meta.stringToEnum(Command, tokens.first()) orelse continue;
        switch (command) {
            .SET => {
                const key = tokens.next() orelse "";
                const value = tokens.next() orelse "";
                try cache.set(gpa, key, value);
            },
            .GET => {
                try out.writeAll(cache.get(tokens.next() orelse "") orelse "NULL");
                try out.writeByte('\n');
            },
            .DEL => try out.writeAll(if (cache.remove(tokens.next() orelse "")) "1\n" else "0\n"),
            .SIZE => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

/// Yields `\n`-terminated lines with any trailing `\r` removed. A final
/// newline does not produce an extra empty line.
const LineIterator = struct {
    rest: []const u8,

    fn next(self: *LineIterator) ?[]const u8 {
        if (self.rest.len == 0) return null;
        const end = std.mem.indexOfScalar(u8, self.rest, '\n');
        var line = self.rest[0 .. end orelse self.rest.len];
        self.rest = if (end) |e| self.rest[e + 1 ..] else &.{};
        if (std.mem.endsWith(u8, line, "\r")) line.len -= 1;
        return line;
    }
};

/// Parses the leading decimal digits of `s`, ignoring anything after them.
/// Saturates at the largest capacity the cache supports.
fn parseCapacity(s: []const u8) usize {
    var value: usize = 0;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) break;
        value = value *| 10 +| (c - '0');
    }
    return @min(value, LruCache.max_capacity);
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var output: Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try run(std.testing.allocator, input, &output.writer);
    try std.testing.expectEqualStrings(expected, output.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "del and size without trailing newline" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "crlf line endings and unknown commands" {
    try expectRun("1\r\nSET a 1\r\nNOPE\r\n\r\nGET a\r\n", "1\n");
}

test "empty input" {
    try expectRun("", "");
}

test "parseCapacity" {
    try std.testing.expectEqual(42, parseCapacity("42 extra"));
    try std.testing.expectEqual(0, parseCapacity("x"));
    try std.testing.expectEqual(LruCache.max_capacity, parseCapacity("99999999999999999999999"));
}

test {
    _ = LruCache;
}
