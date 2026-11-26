//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes the results of GET, DEL and SIZE to stdout.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("LruCache.zig");

/// Longest accepted input line; far above the spec's ~135-byte maximum.
const max_line_len = 1 << 20;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buf: [max_line_len]u8 = undefined;
    var stdin_reader = Io.File.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writerStreaming(io, &out_buf);

    run(init.gpa, &stdin_reader.interface, &stdout_writer.interface) catch |err| switch (err) {
        error.InvalidCapacity => {
            std.log.err("first line must be the cache capacity", .{});
            std.process.exit(1);
        },
        else => |e| return e,
    };
    try stdout_writer.interface.flush();
}

pub const RunError = error{ InvalidCapacity, OutOfMemory } ||
    Io.Reader.DelimiterError || Io.Writer.Error;

/// Processes the whole input from `in`, writing results to `out`.
pub fn run(gpa: std.mem.Allocator, in: *Io.Reader, out: *Io.Writer) RunError!void {
    const first_line = try readLine(in) orelse return;
    const capacity = std.fmt.parseInt(i64, trim(first_line), 10) catch
        return error.InvalidCapacity;
    if (capacity < 0) return error.InvalidCapacity;

    var cache: LruCache = try .init(gpa, std.math.cast(usize, capacity) orelse std.math.maxInt(usize));
    defer cache.deinit();

    while (try readLine(in)) |raw| {
        const line = trim(raw);
        if (line.len != 0) try execute(&cache, out, line);
    }
}

fn readLine(in: *Io.Reader) error{ ReadFailed, StreamTooLong }!?[]u8 {
    return in.takeDelimiter('\n');
}

/// Strips leading and trailing whitespace and control characters.
fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    var end = s.len;
    while (start < end and s[start] <= ' ') start += 1;
    while (end > start and s[end - 1] <= ' ') end -= 1;
    return s[start..end];
}

const Command = enum { SET, GET, DEL, SIZE };

/// Runs one (trimmed, non-empty) command line. Unknown commands and SET lines
/// missing a value are ignored.
fn execute(cache: *LruCache, out: *Io.Writer, line: []const u8) !void {
    const space = std.mem.indexOfScalar(u8, line, ' ');
    const name = line[0 .. space orelse line.len];
    // The argument is everything after the first space. A bare GET/DEL uses
    // the whole line as its key, matching the reference implementation.
    const arg = if (space) |s| line[s + 1 ..] else line;

    const command = std.meta.stringToEnum(Command, name) orelse return;
    switch (command) {
        .SET => {
            if (space == null) return;
            const sep = std.mem.indexOfScalar(u8, arg, ' ') orelse return;
            try cache.put(arg[0..sep], arg[sep + 1 ..]);
        },
        .GET => try emit(out, cache.get(arg) orelse "NULL"),
        .DEL => try emit(out, if (cache.remove(arg)) "1" else "0"),
        .SIZE => try out.print("{d}\n", .{cache.count()}),
    }
}

fn emit(out: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try out.writeAll(s);
    try out.writeByte('\n');
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "tolerates CRLF, blank lines, unknown commands and a missing final newline" {
    try expectOutput("1\r\n\r\nSET a 1\r\nNOPE x\nSET b\n  GET a  \nSIZE", "1\n1\n");
}

test "empty input produces no output" {
    try expectOutput("", "");
}

test "invalid capacity is rejected" {
    try std.testing.expectError(error.InvalidCapacity, expectOutput("x\n", ""));
    try std.testing.expectError(error.InvalidCapacity, expectOutput("-1\n", ""));
}

test {
    _ = LruCache;
}
