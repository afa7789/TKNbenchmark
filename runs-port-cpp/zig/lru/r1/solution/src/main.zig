//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes the result of each query command to stdout.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A fixed-capacity least-recently-used cache.
///
/// Keys and values are borrowed slices: the caller must keep the bytes alive
/// for as long as they may be held by the cache. Each map entry carries its
/// links in a doubly linked recency list (head = most recently used), threaded
/// through entry indices, so every operation runs in O(1) expected time.
pub const LruCache = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Entry = struct {
        value: []const u8,
        prev: Index = none,
        next: Index = none,
    };

    /// `ArrayHashMap` deletes by backward shifting rather than tombstones, so
    /// heavy insert/delete churn cannot degrade lookups.
    const Map = std.StringArrayHashMapUnmanaged(Entry);

    capacity: usize,
    map: Map = .empty,
    /// Most recently used entry, or `none` when empty.
    head: Index = none,
    /// Least recently used entry, or `none` when empty.
    tail: Index = none,

    pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!LruCache {
        var cache: LruCache = .{ .capacity = capacity };
        // One extra slot: an insert briefly exceeds capacity before evicting.
        try cache.map.ensureTotalCapacity(gpa, @min(capacity +| 1, 1 << 20));
        return cache;
    }

    pub fn deinit(self: *LruCache, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const LruCache) usize {
        return self.map.count();
    }

    /// Inserts or overwrites `key`, making it the most recently used, then
    /// evicts the least recently used entry if the cache is over capacity.
    pub fn set(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        const i: Index = @intCast(gop.index);
        if (gop.found_existing) {
            gop.value_ptr.value = value;
            self.touch(i);
            return;
        }
        gop.value_ptr.* = .{ .value = value };
        self.pushFront(i);
        if (self.map.count() > self.capacity) self.removeAt(self.tail);
    }

    /// Looks up `key`; a hit makes it the most recently used. The returned
    /// slice is the borrowed value passed to `set`.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const i: Index = @intCast(self.map.getIndex(key) orelse return null);
        self.touch(i);
        return self.map.values()[i].value;
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const i: Index = @intCast(self.map.getIndex(key) orelse return false);
        self.removeAt(i);
        return true;
    }

    fn removeAt(self: *LruCache, i: Index) void {
        self.unlink(i);
        const last: Index = @intCast(self.map.count() - 1);
        self.map.swapRemoveAt(i);
        if (i == last) return;

        // The former last entry now lives at `i`; repoint its neighbours.
        const entries = self.map.values();
        const moved = entries[i];
        if (moved.prev != none) entries[moved.prev].next = i else self.head = i;
        if (moved.next != none) entries[moved.next].prev = i else self.tail = i;
    }

    fn touch(self: *LruCache, i: Index) void {
        if (self.head == i) return;
        self.unlink(i);
        self.pushFront(i);
    }

    fn pushFront(self: *LruCache, i: Index) void {
        const entries = self.map.values();
        entries[i].prev = none;
        entries[i].next = self.head;
        if (self.head != none) entries[self.head].prev = i else self.tail = i;
        self.head = i;
    }

    fn unlink(self: *LruCache, i: Index) void {
        const entries = self.map.values();
        const entry = entries[i];
        if (entry.prev != none) entries[entry.prev].next = entry.next else self.head = entry.next;
        if (entry.next != none) entries[entry.next].prev = entry.prev else self.tail = entry.prev;
    }
};

/// Strips trailing `\r`, spaces and tabs, and leading spaces and tabs.
fn trimLine(line: []const u8) []const u8 {
    const trailing = std.mem.trimEnd(u8, line, "\r \t");
    return std.mem.trimStart(u8, trailing, " \t");
}

/// Parses the leading decimal digits of `text`; yields 0 if there are none
/// or the number does not fit.
fn parseCapacity(text: []const u8) usize {
    const digits = for (text, 0..) |c, i| {
        if (!std.ascii.isDigit(c)) break text[0..i];
    } else text;
    return std.fmt.parseUnsigned(usize, digits, 10) catch 0;
}

/// Executes every command in `input`, writing query results to `out`.
/// Keys and values stored in the cache borrow from `input`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    var cache: LruCache = try .init(gpa, parseCapacity(trimLine(first)));
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        var tokens = std.mem.splitScalar(u8, trimLine(raw), ' ');
        const cmd = tokens.first();
        if (std.mem.eql(u8, cmd, "SET")) {
            const key = tokens.next() orelse "";
            const value = tokens.next() orelse "";
            try cache.set(gpa, key, value);
        } else if (std.mem.eql(u8, cmd, "GET")) {
            try out.writeAll(cache.get(tokens.next() orelse "") orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            try out.writeAll(if (cache.remove(tokens.next() orelse "")) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &.{});
    const input = try stdin_reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [1 << 16]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout_writer.interface;
    try run(gpa, input, out);
    try out.flush();
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectRun("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one with CRLF line endings" {
    try expectRun("1\r\nSET a 1\r\nSET b 2\r\nGET a\r\nGET b\r\nSIZE\r\n", "NULL\n2\n1\n");
}

test "recency survives entry relocation on removal" {
    var cache: LruCache = try .init(std.testing.allocator, 2);
    defer cache.deinit(std.testing.allocator);
    const gpa = std.testing.allocator;
    try cache.set(gpa, "a", "1");
    try cache.set(gpa, "b", "2");
    try std.testing.expect(cache.remove("a"));
    try cache.set(gpa, "c", "3");
    try cache.set(gpa, "d", "4");
    try std.testing.expectEqual(@as(?[]const u8, null), cache.get("b"));
    try std.testing.expectEqualStrings("3", cache.get("c").?);
    try std.testing.expectEqualStrings("4", cache.get("d").?);
    try std.testing.expectEqual(@as(usize, 2), cache.count());
    try cache.set(gpa, "e", "5");
    try std.testing.expectEqual(@as(?[]const u8, null), cache.get("c"));
    try std.testing.expectEqualStrings("5", cache.get("e").?);
}

test "parse capacity" {
    try std.testing.expectEqual(@as(usize, 42), parseCapacity("42"));
    try std.testing.expectEqual(@as(usize, 7), parseCapacity("7x"));
    try std.testing.expectEqual(@as(usize, 0), parseCapacity("abc"));
}
