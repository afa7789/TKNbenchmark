//! Reads LRU cache commands from standard input and writes results to
//! standard output. See SPEC.md for the command language.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const LruCache = @import("LruCache.zig");

const io_buffer_size = 1 << 16;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var stdin_buffer: [io_buffer_size]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
    // The whole input is kept in memory so the cache can borrow keys and
    // values from it instead of copying each one.
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [io_buffer_size]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    const out = &stdout_writer.interface;

    run(gpa, input, out) catch |err| switch (err) {
        error.InvalidCapacity => {
            std.log.err("first line must be a positive integer capacity", .{});
            std.process.exit(1);
        },
        else => |e| return e,
    };
    try out.flush();
}

pub const RunError = Allocator.Error || Writer.Error || error{InvalidCapacity};

/// Executes every command in `input`, writing results to `out`.
/// Keys and values are borrowed from `input`.
pub fn run(gpa: Allocator, input: []const u8, out: *Writer) RunError!void {
    if (input.len == 0) return;

    // Lines end at `\n`, `\r`, or `\r\n`. Blank lines are ignored, so the
    // command lines can simply be tokenized on either terminator.
    const header_end = std.mem.indexOfAny(u8, input, "\r\n") orelse input.len;
    const capacity = try parseCapacity(input[0..header_end]);

    var cache: LruCache = try .init(gpa, capacity);
    defer cache.deinit(gpa);

    var lines = std.mem.tokenizeAny(u8, input[header_end..], "\r\n");
    while (lines.next()) |line| try execute(gpa, &cache, line, out);
}

const Command = enum { SET, GET, DEL, SIZE };

/// Runs one command line. Unrecognised or malformed lines are ignored.
fn execute(gpa: Allocator, cache: *LruCache, line: []const u8, out: *Writer) !void {
    const first_space = std.mem.indexOfScalar(u8, line, ' ');
    const name = if (first_space) |i| line[0..i] else line;
    const command = std.meta.stringToEnum(Command, name) orelse return;
    switch (command) {
        .SET => {
            const args = line[(first_space orelse return) + 1 ..];
            const second_space = std.mem.indexOfScalar(u8, args, ' ') orelse return;
            try cache.put(gpa, args[0..second_space], args[second_space + 1 ..]);
        },
        .GET => {
            const key = line[(first_space orelse return) + 1 ..];
            try writeLine(out, cache.get(key) orelse "NULL");
        },
        .DEL => {
            const key = line[(first_space orelse return) + 1 ..];
            try writeLine(out, if (cache.remove(key)) "1" else "0");
        },
        .SIZE => try out.print("{d}\n", .{cache.count()}),
    }
}

fn writeLine(out: *Writer, text: []const u8) Writer.Error!void {
    try out.writeAll(text);
    try out.writeByte('\n');
}

/// Parses the header line: optional surrounding whitespace, an optional `+`,
/// then a decimal integer in 1...maxInt(i32).
fn parseCapacity(line: []const u8) error{InvalidCapacity}!u32 {
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    const digits = if (std.mem.startsWith(u8, trimmed, "+")) trimmed[1..] else trimmed;
    if (digits.len == 0) return error.InvalidCapacity;
    for (digits) |c| if (!std.ascii.isDigit(c)) return error.InvalidCapacity;
    const value = std.fmt.parseInt(i32, digits, 10) catch return error.InvalidCapacity;
    if (value < 1) return error.InvalidCapacity;
    return @intCast(value);
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var out: Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "del and size without trailing newline" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "carriage returns, blank and malformed lines" {
    try expectOutput("1\r\nSET a 1\r\n\r\nSET b\nGET\nFOO a\nGET a\r\nSIZE extra\n", "1\n1\n");
}

test "value keeps everything after the second space" {
    try expectOutput("2\nSET k a b\nGET k\n", "a b\n");
}

test "empty input produces no output" {
    try expectOutput("", "");
}

test "invalid capacity" {
    try std.testing.expectError(error.InvalidCapacity, expectOutput("0\nSIZE\n", ""));
    try std.testing.expectError(error.InvalidCapacity, expectOutput("1_0\n", ""));
    try std.testing.expectError(error.InvalidCapacity, expectOutput("\nSIZE\n", ""));
    try expectOutput(" +3 \nSIZE\n", "0\n");
}

test {
    _ = LruCache;
}
