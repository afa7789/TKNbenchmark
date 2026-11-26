//! `app lru`: see the "lru" section of SPEC.md.
//!
//! Reads a capacity line followed by one command per line from standard
//! input, applies the commands to an LRU cache and writes their results to
//! standard output, one per line.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Cache = @import("Cache.zig");

/// Runs the subcommand: reads standard input, writes standard output.
pub fn run(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);

    try simulate(init.gpa, &stdin.interface, &stdout.interface);
    try stdout.interface.flush();
}

/// Reads the capacity and the commands from `in` and writes the outputs to
/// `out`. Lines that are not well-formed commands are ignored.
pub fn simulate(gpa: Allocator, in: *Io.Reader, out: *Io.Writer) !void {
    const first = try in.takeDelimiter('\n') orelse return;
    const capacity = std.fmt.parseUnsigned(usize, std.mem.trim(u8, first, " \t\r"), 10) catch return error.InvalidCapacity;
    if (capacity < 1 or capacity > Cache.max_capacity) return error.InvalidCapacity;

    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);

    while (try in.takeDelimiter('\n')) |line| {
        const command = Command.parse(trimLine(line)) orelse continue;
        switch (command) {
            .set => |args| try cache.set(gpa, args.key, args.value),
            .get => |key| try out.print("{s}\n", .{cache.get(key) orelse "NULL"}),
            .del => |key| try out.writeAll(if (cache.del(key)) "1\n" else "0\n"),
            .size => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

/// Strips a trailing carriage return so CRLF input is accepted too.
fn trimLine(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

const Command = union(enum) {
    set: struct { key: []const u8, value: []const u8 },
    get: []const u8,
    del: []const u8,
    size,

    /// Parses one command line, or returns null if it is malformed.
    fn parse(line: []const u8) ?Command {
        var tokens = std.mem.splitScalar(u8, line, ' ');
        const name = tokens.first();
        const command: Command = if (std.mem.eql(u8, name, "SET")) blk: {
            const key = token(&tokens) orelse return null;
            const value = token(&tokens) orelse return null;
            break :blk .{ .set = .{ .key = key, .value = value } };
        } else if (std.mem.eql(u8, name, "GET"))
            .{ .get = token(&tokens) orelse return null }
        else if (std.mem.eql(u8, name, "DEL"))
            .{ .del = token(&tokens) orelse return null }
        else if (std.mem.eql(u8, name, "SIZE"))
            .size
        else
            return null;
        if (tokens.next() != null) return null;
        return command;
    }

    fn token(tokens: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
        const t = tokens.next() orelse return null;
        if (t.len == 0 or t.len > Cache.max_len) return null;
        return t;
    }
};

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try simulate(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "last line without newline" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "crlf and malformed lines" {
    try expectOutput("1\r\nSET a 1\r\n\nBOGUS\nGET\nGET a b\nGET a\r\nSIZE", "1\n1\n");
}

test "empty input" {
    try expectOutput("", "");
}

test "invalid capacity" {
    var in: Io.Reader = .fixed("0\nSIZE\n");
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expectError(error.InvalidCapacity, simulate(std.testing.allocator, &in, &out.writer));
}

test {
    _ = Cache;
}
