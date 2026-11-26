//! Reads an LRU cache capacity and a stream of commands from standard input
//! and writes each command's result to standard output. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("lru.zig").LruCache;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    run(gpa, input, out) catch |err| switch (err) {
        error.InvalidCapacity => {
            std.log.err("first line must be a capacity between 1 and {d}", .{max_capacity});
            std.process.exit(1);
        },
        else => |e| return e,
    };
    try out.flush();
}

const max_capacity = 1_000_000;

const RunError = error{InvalidCapacity} || std.mem.Allocator.Error || Io.Writer.Error;

/// Executes every command in `input`, writing results to `out`. Keys and
/// values stored in the cache borrow from `input`.
fn run(gpa: std.mem.Allocator, input: []const u8, out: *Io.Writer) RunError!void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const header = lines.next() orelse return;
    if (header.len == 0 and lines.peek() == null) return; // empty input

    var cache: LruCache([]const u8) = .init(try parseCapacity(stripCr(header)));
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = stripCr(raw);
        if (line.len == 0) continue;

        const space = std.mem.indexOfScalar(u8, line, ' ');
        const command = line[0 .. space orelse line.len];
        // A bare command with no argument uses the whole line as its key,
        // matching the reference implementation.
        const arg = if (space) |s| line[s + 1 ..] else line;

        if (std.mem.eql(u8, command, "SET")) {
            const sep = std.mem.indexOfScalar(u8, arg, ' ') orelse continue;
            try cache.put(gpa, arg[0..sep], arg[sep + 1 ..]);
        } else if (std.mem.eql(u8, command, "GET")) {
            try out.writeAll(cache.get(arg) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, command, "DEL")) {
            try out.writeAll(if (cache.remove(arg)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, command, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
        // Unknown commands are ignored; the spec defines no output for them.
    }
}

fn stripCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

/// Parses the leading decimal digits of the header, ignoring surrounding
/// whitespace and any trailing text.
fn parseCapacity(header: []const u8) error{InvalidCapacity}!u32 {
    const text = std.mem.trim(u8, header, &std.ascii.whitespace);
    var end: usize = 0;
    while (end < text.len and std.ascii.isDigit(text[end])) end += 1;
    const capacity = std.fmt.parseInt(u32, text[0..end], 10) catch return error.InvalidCapacity;
    if (capacity < 1 or capacity > max_capacity) return error.InvalidCapacity;
    return capacity;
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

test "crlf, blank lines, missing final newline, unknown commands" {
    try expectOutput("1\r\n\r\nSET a 1\r\nNOPE x\nGET a\r\n\nDEL a", "1\n1\n");
}

test "empty input produces nothing" {
    try expectOutput("", "");
}

test "invalid capacity" {
    try std.testing.expectError(error.InvalidCapacity, parseCapacity("0"));
    try std.testing.expectError(error.InvalidCapacity, parseCapacity("abc"));
    try std.testing.expectEqual(5, try parseCapacity(" 5 "));
}

test {
    _ = @import("lru.zig");
}
