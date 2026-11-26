//! `app lru`: LRU cache simulator. See the "lru" section of SPEC.md.
//!
//! The first line holds the capacity; every later line is one command
//! (`SET <key> <value>`, `GET <key>`, `DEL <key>` or `SIZE`). Input is
//! streamed line by line, so memory is bounded by the cache contents rather
//! than by the input size. Lines that are not a well-formed command are
//! ignored, as is all input after an invalid capacity line.

const std = @import("std");
const Io = std.Io;

pub const Cache = @import("Cache.zig");

const max_capacity = 1_000_000;

/// Runs the subcommand: reads standard input and writes standard output.
/// Must exit with status 0 on any input, per SPEC.md.
pub fn run(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);

    simulate(init.gpa, &stdin.interface, &stdout.interface) catch |err| switch (err) {
        error.ReadFailed => return stdin.err.?,
        error.WriteFailed => return stdout.err.?,
        else => |e| return e,
    };
    stdout.interface.flush() catch return stdout.err.?;
}

pub const SimulateError = Io.Reader.Error || Io.Writer.Error || Cache.InitError;

/// Executes the commands read from `in`, writing their output to `out`.
/// The caller is responsible for flushing `out`.
pub fn simulate(gpa: std.mem.Allocator, in: *Io.Reader, out: *Io.Writer) SimulateError!void {
    const first = try nextLine(in) orelse return;
    const capacity = parseCapacity(first) orelse return;

    var cache: Cache = try .init(gpa, capacity);
    defer cache.deinit();

    while (try nextLine(in)) |line| {
        const command = Command.parse(line) orelse continue;
        switch (command) {
            .set => |set| try cache.put(set.key, set.value),
            .get => |key| try out.print("{s}\n", .{cache.get(key) orelse "NULL"}),
            .del => |key| try out.print("{d}\n", .{@intFromBool(cache.remove(key))}),
            .size => try out.print("{d}\n", .{cache.count()}),
        }
    }
}

/// Returns the next line without its terminator (`\n`, or `\r\n`), or null at
/// end of input. Lines too long to buffer cannot be valid commands; they are
/// skipped.
fn nextLine(in: *Io.Reader) Io.Reader.Error!?[]const u8 {
    while (true) {
        const line = in.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                _ = in.discardDelimiterInclusive('\n') catch |e| switch (e) {
                    error.EndOfStream => return null,
                    error.ReadFailed => return error.ReadFailed,
                };
                continue;
            },
            error.ReadFailed => return error.ReadFailed,
        } orelse return null;
        return std.mem.trimEnd(u8, line, "\r");
    }
}

fn parseCapacity(line: []const u8) ?usize {
    const trimmed = std.mem.trim(u8, line, " \t");
    const capacity = std.fmt.parseUnsigned(usize, trimmed, 10) catch return null;
    if (capacity < 1 or capacity > max_capacity) return null;
    return capacity;
}

const Command = union(enum) {
    set: struct { key: []const u8, value: []const u8 },
    get: []const u8,
    del: []const u8,
    size,

    const Name = enum { SET, GET, DEL, SIZE };

    /// Parses one command line, or returns null if it is malformed.
    fn parse(line: []const u8) ?Command {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const name = std.meta.stringToEnum(Name, tokens.next() orelse return null) orelse
            return null;
        const command: Command = switch (name) {
            .SET => .{ .set = .{
                .key = validToken(tokens.next()) orelse return null,
                .value = validToken(tokens.next()) orelse return null,
            } },
            .GET => .{ .get = validToken(tokens.next()) orelse return null },
            .DEL => .{ .del = validToken(tokens.next()) orelse return null },
            .SIZE => .size,
        };
        if (tokens.next() != null) return null;
        return command;
    }

    fn validToken(token: ?[]const u8) ?[]const u8 {
        const t = token orelse return null;
        return if (t.len <= Cache.max_len) t else null;
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

test "delete and size" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "last line without newline and CRLF endings" {
    try expectOutput("1\r\nSET a 1\r\nGET a", "1\n");
}

test "malformed lines are ignored" {
    try expectOutput("2\n\nFOO a\nGET\nSET a\nSET a 1 2\nSIZE x\nSIZE\n", "0\n");
}

test "invalid capacity produces no output" {
    try expectOutput("0\nSIZE\n", "");
    try expectOutput("abc\nSIZE\n", "");
    try expectOutput("", "");
}

test {
    std.testing.refAllDecls(@This());
}
