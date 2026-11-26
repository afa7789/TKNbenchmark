//! Reads a capacity followed by cache commands from standard input and writes
//! command results to standard output, one per line.

const std = @import("std");
const Io = std.Io;
const LruCache = @import("LruCache.zig");

const buffer_size = 1 << 16;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdin_buffer: [buffer_size]u8 = undefined;
    var stdin_reader: Io.File.Reader = .initStreaming(.stdin(), io, &stdin_buffer);
    var stdout_buffer: [buffer_size]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);

    try run(init.gpa, &stdin_reader.interface, &stdout_writer.interface);
    try stdout_writer.interface.flush();
}

/// Errors that `run` may return.
pub const RunError = LruCache.InitError || Io.Reader.DelimiterError || Io.Writer.Error ||
    std.fmt.ParseIntError;

pub fn run(gpa: std.mem.Allocator, in: *Io.Reader, out: *Io.Writer) RunError!void {
    var lines: LineIterator = .{ .reader = in };

    const header = try lines.next() orelse return;
    const capacity = try std.fmt.parseInt(u32, std.mem.trim(u8, header, &std.ascii.whitespace), 10);

    var cache: LruCache = try .init(gpa, capacity);
    defer cache.deinit();

    while (try lines.next()) |line| try execute(&cache, line, out);
}

fn execute(cache: *LruCache, line: []const u8, out: *Io.Writer) !void {
    const first_space = std.mem.indexOfScalar(u8, line, ' ');
    const command = line[0 .. first_space orelse line.len];
    const rest = if (first_space) |i| line[i + 1 ..] else null;

    if (std.mem.eql(u8, command, "SET")) {
        const args = rest orelse return;
        const second_space = std.mem.indexOfScalar(u8, args, ' ') orelse return;
        try cache.put(args[0..second_space], args[second_space + 1 ..]);
    } else if (std.mem.eql(u8, command, "GET")) {
        const key = rest orelse return;
        try writeLine(out, cache.get(key) orelse "NULL");
    } else if (std.mem.eql(u8, command, "DEL")) {
        const key = rest orelse return;
        try writeLine(out, if (cache.remove(key)) "1" else "0");
    } else if (std.mem.eql(u8, command, "SIZE")) {
        try out.print("{d}\n", .{cache.size()});
    }
    // Blank or unrecognised lines are ignored.
}

fn writeLine(out: *Io.Writer, text: []const u8) Io.Writer.Error!void {
    try out.writeAll(text);
    try out.writeByte('\n');
}

/// Yields lines terminated by `\n`, `\r`, or `\r\n`, without the terminator.
/// A final line lacking a terminator is still yielded.
/// Returned slices are valid until the next call to `next`.
const LineIterator = struct {
    reader: *Io.Reader,
    /// Remaining `\r`-separated pieces of the most recently read `\n` line.
    pending: ?std.mem.SplitIterator(u8, .scalar) = null,

    fn next(it: *LineIterator) Io.Reader.DelimiterError!?[]const u8 {
        if (it.pending) |*pieces| {
            if (pieces.next()) |piece| return piece;
            it.pending = null;
        }
        var line = (try it.reader.takeDelimiter('\n')) orelse return null;
        if (std.mem.endsWith(u8, line, "\r")) line = line[0 .. line.len - 1];
        it.pending = std.mem.splitScalar(u8, line, '\r');
        return it.pending.?.next().?;
    }
};

fn expectRun(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "del and size without trailing newline" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "carriage returns and ignored lines" {
    try expectRun("2\r\nSET a 1\r\n\r\nBOGUS\rGET a\rGET\nSIZE", "1\n1\n");
}

test "empty input" {
    try expectRun("", "");
}

test {
    _ = LruCache;
}
