//! `app lru` — see the "lru" section of SPEC.md.
//!
//! The first input line is the cache capacity; every later line is a `SET`,
//! `GET`, `DEL` or `SIZE` command, executed in O(1) expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Cache = @import("Cache.zig");

pub const Error = error{
    MissingCapacity,
    InvalidCapacity,
    InvalidCommand,
} || Allocator.Error || Io.Reader.DelimiterError || Io.Writer.Error;

/// LRU cache simulator: execute the commands read from `in`.
///
/// `in` is standard input and `out` is buffered standard output; the caller
/// flushes `out` after this returns. `gpa` is a general-purpose allocator.
pub fn run(gpa: Allocator, in: *Io.Reader, out: *Io.Writer) Error!void {
    const first = try in.takeDelimiter('\n') orelse return error.MissingCapacity;
    const capacity = parseCapacity(first) orelse return error.InvalidCapacity;

    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);

    while (try in.takeDelimiter('\n')) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        try execute(gpa, &cache, line, out);
    }
}

fn parseCapacity(line: []const u8) ?u32 {
    const text = std.mem.trim(u8, line, " \t\r");
    const capacity = std.fmt.parseUnsigned(u32, text, 10) catch return null;
    if (capacity < 1 or capacity > Cache.max_capacity) return null;
    return capacity;
}

const Command = enum { SET, GET, DEL, SIZE };

fn execute(gpa: Allocator, cache: *Cache, line: []const u8, out: *Io.Writer) Error!void {
    var tokens = std.mem.splitScalar(u8, line, ' ');
    const name = tokens.first();
    const command = std.meta.stringToEnum(Command, name) orelse return error.InvalidCommand;
    switch (command) {
        .SET => {
            const key = try token(&tokens);
            const value = try token(&tokens);
            try end(&tokens);
            try cache.set(gpa, key, value);
        },
        .GET => {
            const key = try token(&tokens);
            try end(&tokens);
            try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
        },
        .DEL => {
            const key = try token(&tokens);
            try end(&tokens);
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        },
        .SIZE => {
            try end(&tokens);
            try out.print("{d}\n", .{cache.size()});
        },
    }
}

/// Returns the next key or value token, which must be 1–64 bytes long.
fn token(tokens: *std.mem.SplitIterator(u8, .scalar)) error{InvalidCommand}![]const u8 {
    const t = tokens.next() orelse return error.InvalidCommand;
    if (t.len == 0 or t.len > Cache.max_token_len) return error.InvalidCommand;
    return t;
}

fn end(tokens: *std.mem.SplitIterator(u8, .scalar)) error{InvalidCommand}!void {
    if (tokens.next() != null) return error.InvalidCommand;
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var in: Io.Reader = .fixed(input);
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, &in, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test run {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectOutput("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one" {
    try expectOutput("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
}

test "get refreshes recency" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\nGET c\n", "1\n1\nNULL\n3\n");
}

test "deleted slots are reused" {
    try expectOutput("2\nSET a 1\nDEL a\nSET b 2\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n");
}

test "invalid capacity" {
    var out: Io.Writer.Discarding = .init(&.{});
    var zero: Io.Reader = .fixed("0\n");
    try std.testing.expectError(error.InvalidCapacity, run(std.testing.allocator, &zero, &out.writer));
    var empty: Io.Reader = .fixed("");
    try std.testing.expectError(error.MissingCapacity, run(std.testing.allocator, &empty, &out.writer));
}

test {
    std.testing.refAllDecls(@This());
}
