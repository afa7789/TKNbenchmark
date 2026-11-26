//! Reads an LRU capacity and a list of cache commands from stdin and writes
//! the command results to stdout. See SPEC.md.

const std = @import("std");
const LruCache = @import("lru.zig").LruCache;

const max_capacity = 1_000_000;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    // The cache borrows keys and values from this buffer, so it must outlive it.
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    const out = &stdout.interface;

    run(gpa, input, out) catch |err| switch (err) {
        error.WriteFailed => return stdout.err.?,
        else => |e| return e,
    };
    try out.flush();
}

const RunError = error{ InvalidCapacity, OutOfMemory, WriteFailed };

fn run(gpa: std.mem.Allocator, input: []const u8, out: *std.Io.Writer) RunError!void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = try parseCapacity(lines.first());

    var cache: LruCache = .init(gpa, capacity);
    defer cache.deinit();

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;

        var tokens = std.mem.splitScalar(u8, line, ' ');
        const command = tokens.first();
        const key = tokens.next() orelse "";

        if (std.mem.eql(u8, command, "SET")) {
            try cache.put(key, tokens.next() orelse "");
        } else if (std.mem.eql(u8, command, "GET")) {
            try out.writeAll(cache.get(key) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, command, "DEL")) {
            try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, command, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
        // Unknown commands are ignored.
    }
}

fn parseCapacity(line: []const u8) error{InvalidCapacity}!u32 {
    const text = std.mem.trim(u8, line, " \t\r");
    const capacity = std.fmt.parseInt(u32, text, 10) catch return error.InvalidCapacity;
    if (capacity < 1 or capacity > max_capacity) return error.InvalidCapacity;
    return capacity;
}

test "spec example" {
    var buf: [256]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try run(std.testing.allocator, "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", &out);
    try std.testing.expectEqualStrings("1\nNULL\n2\n", out.buffered());
}

test "crlf and missing final newline" {
    var buf: [256]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try run(std.testing.allocator, "1\r\nSET a 1\r\n\r\nGET a\r\nDEL a", &out);
    try std.testing.expectEqualStrings("1\n1\n", out.buffered());
}

test {
    _ = @import("lru.zig");
}
