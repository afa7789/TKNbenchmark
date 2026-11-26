//! Reads a capacity followed by cache commands on stdin and writes one reply
//! line per GET, DEL and SIZE command to stdout. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const LruCache = @import("LruCache.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_buffer: [64 * 1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &stdin_buffer);
    // The cache borrows keys and values from the input, so it must outlive the cache.
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    try run(gpa, input, out);
    try out.flush();
}

/// Executes the command script in `input`, writing replies to `out`.
/// An invalid capacity line produces no output; malformed or unknown commands
/// are ignored.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const requested = parseCapacity(lines.first()) orelse return;

    // Each command line adds at most one key, so a capacity beyond the line
    // count behaves identically; clamping it bounds preallocation.
    const line_count = std.mem.countScalar(u8, input, '\n') + 1;
    const capacity: usize = @intCast(@min(requested, line_count));

    var cache: LruCache = try .init(gpa, capacity, line_count);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = if (std.mem.endsWith(u8, raw, "\r")) raw[0 .. raw.len - 1] else raw;
        if (line.len == 0) continue;

        const command, const rest = std.mem.cutScalar(u8, line, ' ') orelse .{ line, "" };
        const kind = std.meta.stringToEnum(Command, command) orelse continue;
        switch (kind) {
            .SET => {
                const key, const value = std.mem.cutScalar(u8, rest, ' ') orelse continue;
                try cache.put(gpa, key, value);
            },
            .GET => try out.print("{s}\n", .{cache.get(rest) orelse "NULL"}),
            .DEL => try out.writeAll(if (cache.remove(rest)) "1\n" else "0\n"),
            .SIZE => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

const Command = enum { SET, GET, DEL, SIZE };

/// Parses the capacity line with the leniency of JavaScript's `parseInt`:
/// leading whitespace, an optional sign, then decimal digits, ignoring any
/// trailing text. Returns null unless the result is a positive integer.
/// Values too large to represent saturate.
fn parseCapacity(line: []const u8) ?u64 {
    var i: usize = 0;
    while (i < line.len and isJsWhitespace(line[i])) i += 1;

    var negative = false;
    if (i < line.len and (line[i] == '+' or line[i] == '-')) {
        negative = line[i] == '-';
        i += 1;
    }

    const digits_start = i;
    var value: u64 = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
        value = std.math.mul(u64, value, 10) catch std.math.maxInt(u64);
        value = std.math.add(u64, value, line[i] - '0') catch std.math.maxInt(u64);
    }

    if (i == digits_start or negative or value == 0) return null;
    return value;
}

/// Whitespace as JavaScript defines it, restricted to single Latin-1 bytes.
fn isJsWhitespace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', 0x0B, 0x0C, '\r', 0xA0 => true,
        else => false,
    };
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "lenient parsing" {
    try expectRun(" 3x\r\nSET a 1 2\r\nGET a\r\n\nBOGUS\nSET b\nGET b\nSIZE", "1 2\nNULL\n1\n");
    try expectRun("SET a 1\nSIZE\n", "");
    try expectRun("0\nSIZE\n", "");
    try expectRun("-4\nSIZE\n", "");
    try expectRun("99999999999999999999999\nSET a 1\nSIZE\n", "1\n");
    try expectRun("", "");
}

test "empty key from GET without argument" {
    try expectRun("2\nSET  v\nGET\nDEL\nSIZE\n", "v\n1\n0\n");
}

test {
    _ = LruCache;
}
