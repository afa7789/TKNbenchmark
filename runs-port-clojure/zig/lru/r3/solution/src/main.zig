//! LRU cache simulator.
//!
//! Reads a capacity on the first line of standard input, then one command per
//! line (`SET <key> <value>`, `GET <key>`, `DEL <key>`, `SIZE`), writing each
//! command's result to standard output on its own line.

const std = @import("std");
const LruCache = @import("LruCache.zig");

/// Bytes stripped from both ends of every line: ASCII controls and space.
const trim_set: [33]u8 = blk: {
    var set: [33]u8 = undefined;
    for (&set, 0..) |*c, i| c.* = @intCast(i);
    break :blk set;
};

/// Longest accepted line; longer lines cannot be valid commands and are skipped.
const max_line_len = 1 << 16;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [max_line_len]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    var out_buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);

    try run(gpa, &stdin.interface, &stdout.interface);
    try stdout.interface.flush();
}

const Lines = struct {
    reader: *std.Io.Reader,

    /// Returns the next trimmed line, skipping over-long ones, or null at end
    /// of input.
    fn next(lines: Lines) std.Io.Reader.Error!?[]const u8 {
        while (true) {
            const line = lines.reader.takeDelimiter('\n') catch |err| switch (err) {
                error.ReadFailed => return error.ReadFailed,
                error.StreamTooLong => {
                    _ = lines.reader.discardDelimiterInclusive('\n') catch |e| switch (e) {
                        error.EndOfStream => return null,
                        error.ReadFailed => return error.ReadFailed,
                    };
                    continue;
                },
            } orelse return null;
            return std.mem.trim(u8, line, &trim_set);
        }
    }
};

fn run(gpa: std.mem.Allocator, in: *std.Io.Reader, out: *std.Io.Writer) !void {
    const lines: Lines = .{ .reader = in };
    const first = try lines.next() orelse return;
    const capacity = std.fmt.parseInt(u32, first, 10) catch return error.InvalidCapacity;

    var cache = try LruCache.init(gpa, capacity);
    defer cache.deinit(gpa);

    while (try lines.next()) |line| {
        if (line.len == 0) continue;
        try execute(gpa, &cache, line, out);
    }
}

/// Runs one non-empty, trimmed command line. Unknown or malformed commands
/// are ignored.
fn execute(gpa: std.mem.Allocator, cache: *LruCache, line: []const u8, out: *std.Io.Writer) !void {
    const space = std.mem.indexOfScalar(u8, line, ' ');
    const op = line[0 .. space orelse line.len];
    const arg = if (space) |i| line[i + 1 ..] else line;

    if (std.mem.eql(u8, op, "SET")) {
        const sep = std.mem.indexOfScalar(u8, arg, ' ') orelse return;
        cache.put(gpa, arg[0..sep], arg[sep + 1 ..]) catch |err| switch (err) {
            error.KeyTooLong, error.ValueTooLong => {},
            error.OutOfMemory => return error.OutOfMemory,
        };
    } else if (std.mem.eql(u8, op, "GET")) {
        try out.writeAll(cache.get(arg) orelse "NULL");
        try out.writeByte('\n');
    } else if (std.mem.eql(u8, op, "DEL")) {
        try out.writeAll(if (cache.remove(arg)) "1\n" else "0\n");
    } else if (std.mem.eql(u8, op, "SIZE")) {
        try out.print("{d}\n", .{cache.count()});
    }
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: std.Io.Reader = .fixed(input);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "delete and size" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "tolerates CRLF, blank lines and unknown commands" {
    try expectOutput("1\r\n\r\nSET a 1\r\nNOPE\nGET a\r\n\nSIZE", "1\n1\n");
}

test {
    _ = LruCache;
}
