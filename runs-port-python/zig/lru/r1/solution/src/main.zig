//! LRU cache simulator.
//!
//! Reads the capacity on the first line of standard input, then one command
//! per line (`SET <key> <value>`, `GET <key>`, `DEL <key>`, `SIZE`), and
//! writes one output line for every command that produces output.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// ASCII whitespace, matching the token separators accepted by the reference.
const whitespace = " \t\r\x0b\x0c";

/// An LRU cache of byte-string keys to byte-string values.
///
/// Entries are stored densely in an array hash map and threaded, by entry
/// index, onto an intrusive doubly linked list ordered from least to most
/// recently used. Removal swaps the last entry into the vacated slot and
/// patches its neighbours, so every operation runs in O(1) expected time
/// without leaving tombstones behind. Keys and values are borrowed slices;
/// the caller keeps them alive.
pub const Cache = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Node = struct {
        value: []const u8,
        prev: Index = none,
        next: Index = none,
    };

    gpa: Allocator,
    capacity: usize,
    map: std.StringArrayHashMapUnmanaged(Node) = .empty,
    /// Least recently used entry.
    head: Index = none,
    /// Most recently used entry.
    tail: Index = none,

    pub fn init(gpa: Allocator, capacity: usize) Cache {
        return .{ .gpa = gpa, .capacity = capacity };
    }

    pub fn deinit(self: *Cache) void {
        self.map.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Cache) usize {
        return self.map.count();
    }

    /// Inserts or overwrites `key`, making it the most recently used, and
    /// evicts the least recently used entry if the capacity is exceeded.
    pub fn set(self: *Cache, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(self.gpa, key);
        const i: Index = @intCast(gop.index);
        if (gop.found_existing) {
            gop.value_ptr.value = value;
            self.touch(i);
            return;
        }
        gop.value_ptr.* = .{ .value = value };
        self.pushBack(i);
        if (self.map.count() > self.capacity) self.removeAt(self.head);
    }

    /// Returns the value for `key`, marking it most recently used on a hit.
    pub fn get(self: *Cache, key: []const u8) ?[]const u8 {
        const i: Index = @intCast(self.map.getIndex(key) orelse return null);
        self.touch(i);
        return self.map.values()[i].value;
    }

    /// Removes `key`; returns whether it was present.
    pub fn remove(self: *Cache, key: []const u8) bool {
        const i: Index = @intCast(self.map.getIndex(key) orelse return false);
        self.removeAt(i);
        return true;
    }

    fn removeAt(self: *Cache, i: Index) void {
        std.debug.assert(i != none);
        self.unlink(i);
        const last: Index = @intCast(self.map.count() - 1);
        self.map.swapRemoveAt(i);
        if (i == last) return;

        // The former last entry now lives at `i`; repoint its neighbours.
        const nodes = self.map.values();
        const moved = nodes[i];
        if (moved.prev != none) nodes[moved.prev].next = i else self.head = i;
        if (moved.next != none) nodes[moved.next].prev = i else self.tail = i;
    }

    fn touch(self: *Cache, i: Index) void {
        if (i == self.tail) return;
        self.unlink(i);
        self.pushBack(i);
    }

    fn unlink(self: *Cache, i: Index) void {
        const nodes = self.map.values();
        const prev = nodes[i].prev;
        const next = nodes[i].next;
        if (prev != none) nodes[prev].next = next else self.head = next;
        if (next != none) nodes[next].prev = prev else self.tail = prev;
        nodes[i].prev = none;
        nodes[i].next = none;
    }

    fn pushBack(self: *Cache, i: Index) void {
        const nodes = self.map.values();
        nodes[i].prev = self.tail;
        nodes[i].next = none;
        if (self.tail != none) nodes[self.tail].next = i else self.head = i;
        self.tail = i;
    }
};

/// Executes the commands in `input` (everything after the capacity line),
/// writing one line per output-producing command to `out`. Blank lines and
/// unrecognised or incomplete commands are ignored.
pub fn run(cache: *Cache, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, whitespace);
        const cmd = tokens.next() orelse continue;
        if (std.mem.eql(u8, cmd, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.set(key, value);
        } else if (std.mem.eql(u8, cmd, "GET")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(cache.get(key) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

/// Parses the capacity line. Non-positive capacities behave like zero.
fn parseCapacity(line: []const u8) !usize {
    const n = try std.fmt.parseInt(i64, std.mem.trim(u8, line, whitespace), 10);
    return std.math.cast(usize, @max(n, 0)) orelse std.math.maxInt(usize);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    const newline = std.mem.indexOfScalar(u8, input, '\n') orelse input.len;
    const first = input[0..newline];
    if (std.mem.trim(u8, first, whitespace).len == 0) return;
    const capacity = parseCapacity(first) catch {
        std.log.err("invalid capacity: '{s}'", .{first});
        std.process.exit(1);
    };
    const rest = if (newline < input.len) input[newline + 1 ..] else "";

    var cache = Cache.init(gpa, capacity);
    defer cache.deinit();

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    try run(&cache, rest, &stdout.interface);
    try stdout.interface.flush();
}

fn expectRun(input: []const u8, capacity: usize, expected: []const u8) !void {
    var cache = Cache.init(std.testing.allocator, capacity);
    defer cache.deinit();
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(&cache, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("SET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", 2, "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectRun("SET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", 2, "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("SET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", 3, "1\n0\n0\nNULL\n");
}

test "entry relocation after delete" {
    try expectRun("SET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", 2, "1\nNULL\n3\n4\n2\n");
}

test "eviction order survives swap removal" {
    try expectRun("SET a 1\nSET b 2\nSET c 3\nGET a\nDEL b\nSET d 4\nSET e 5\nGET c\nGET a\nGET d\nGET e\nSIZE\n", 3, "1\n1\nNULL\n1\n4\n5\n3\n");
}
