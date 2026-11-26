//! Reads LRU cache commands from standard input and writes the results to
//! standard output. See SPEC.md for the command language.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("LruCache.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    run(gpa, input, out) catch |err| switch (err) {
        error.InvalidCapacity => {
            std.log.err("invalid capacity", .{});
            std.process.exit(1);
        },
        else => |e| return e,
    };
    try out.flush();
}

pub const RunError = LruCache.InitError || Io.Writer.Error;

/// Executes every command in `input`. Keys and values are borrowed from
/// `input`, which must outlive the call.
pub fn run(gpa: std.mem.Allocator, input: []const u8, out: *Io.Writer) RunError!void {
    var lines: LineIterator = .{ .data = input };

    const first = while (lines.next()) |line| {
        if (!isBlank(line)) break line;
    } else return;

    var cache: LruCache = try .init(gpa, try parseCapacity(first));
    defer cache.deinit(gpa);

    while (lines.next()) |line| try execute(gpa, &cache, line, out);
}

fn execute(gpa: std.mem.Allocator, cache: *LruCache, line: []const u8, out: *Io.Writer) !void {
    const first_space = std.mem.indexOfScalar(u8, line, ' ');
    const command = line[0 .. first_space orelse line.len];
    const args = if (first_space) |i| line[i + 1 ..] else null;

    if (std.mem.eql(u8, command, "SET")) {
        const rest = args orelse return;
        const second_space = std.mem.indexOfScalar(u8, rest, ' ') orelse return;
        try cache.set(gpa, rest[0..second_space], rest[second_space + 1 ..]);
    } else if (std.mem.eql(u8, command, "GET")) {
        const key = args orelse return;
        try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
    } else if (std.mem.eql(u8, command, "DEL")) {
        const key = args orelse return;
        try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
    } else if (std.mem.eql(u8, command, "SIZE")) {
        try out.print("{d}\n", .{cache.count()});
    }
    // Blank or unrecognised lines produce no output.
}

/// Parses the capacity line: optional surrounding whitespace, an optional
/// sign, and decimal digits forming a positive 32-bit signed integer.
fn parseCapacity(line: []const u8) error{InvalidCapacity}!usize {
    const text = std.mem.trim(u8, line, whitespace);
    const digits = if (text.len > 0 and text[0] == '+') text[1..] else text;
    if (digits.len == 0) return error.InvalidCapacity;
    for (digits) |c| if (!std.ascii.isDigit(c)) return error.InvalidCapacity;
    const value = std.fmt.parseInt(i32, digits, 10) catch return error.InvalidCapacity;
    if (value < 1) return error.InvalidCapacity;
    return @intCast(value);
}

/// Bytes treated as whitespace when locating the capacity line.
const whitespace = " \t\n\r\x0b\x0c\x1c\x1d\x1e\x1f";

fn isBlank(line: []const u8) bool {
    return std.mem.trim(u8, line, whitespace).len == 0;
}

/// Splits a buffer into `\n`-terminated lines, stripping one trailing `\r`
/// and accepting a missing final newline.
const LineIterator = struct {
    data: []const u8,
    pos: usize = 0,

    fn next(it: *LineIterator) ?[]const u8 {
        if (it.pos >= it.data.len) return null;
        const start = it.pos;
        const end = std.mem.indexOfScalarPos(u8, it.data, start, '\n') orelse it.data.len;
        it.pos = end + 1;
        const line = it.data[start..end];
        return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
    }
};

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var buffer: Io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try run(std.testing.allocator, input, &buffer.writer);
    try std.testing.expectEqualStrings(expected, buffer.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "crlf, missing final newline and unknown commands" {
    try expectOutput("\n 1 \r\nSET a 1\r\nNOPE\n\nGET a\r\nDEL a\nSIZE", "1\n1\n0\n");
}

test "capacity validation" {
    try std.testing.expectError(error.InvalidCapacity, parseCapacity("0"));
    try std.testing.expectError(error.InvalidCapacity, parseCapacity("1_0"));
    try std.testing.expectError(error.InvalidCapacity, parseCapacity("x"));
    try std.testing.expectEqual(1_000_000, try parseCapacity(" 1000000\t"));
}

test {
    _ = LruCache;
}
