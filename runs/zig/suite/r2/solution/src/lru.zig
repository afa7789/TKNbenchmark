//! LRU cache simulator. Every command runs in O(1) expected time.
//!
//! Entries live in an array hash map; each entry's value carries the links of an
//! intrusive doubly linked list (by entry index) kept in recency order. The array
//! hash map deletes by swapping with the last entry, which leaves no tombstones,
//! so long SET/DEL/evict churn does not degrade lookups.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Node = struct {
    value: []const u8,
    prev: Index = none,
    next: Index = none,
};

pub const Cache = struct {
    capacity: usize,
    map: std.StringArrayHashMapUnmanaged(Node) = .empty,
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,

    pub fn init(capacity: usize) Cache {
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *Cache, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.* = undefined;
    }

    pub fn size(self: *const Cache) usize {
        return self.map.count();
    }

    /// Keys and values are borrowed and must outlive the cache.
    pub fn set(self: *Cache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        const idx: Index = @intCast(gop.index);
        if (gop.found_existing) {
            gop.value_ptr.value = value;
            self.unlink(idx);
        } else {
            gop.value_ptr.* = .{ .value = value };
        }
        self.pushFront(idx);
        if (self.map.count() > self.capacity) self.remove(self.tail);
    }

    pub fn get(self: *Cache, key: []const u8) ?[]const u8 {
        const idx: Index = @intCast(self.map.getIndex(key) orelse return null);
        self.unlink(idx);
        self.pushFront(idx);
        return self.nodes()[idx].value;
    }

    /// Returns whether the key was present.
    pub fn del(self: *Cache, key: []const u8) bool {
        const idx: Index = @intCast(self.map.getIndex(key) orelse return false);
        self.remove(idx);
        return true;
    }

    fn nodes(self: *const Cache) []Node {
        return self.map.values();
    }

    fn remove(self: *Cache, idx: Index) void {
        self.unlink(idx);
        const last: Index = @intCast(self.map.count() - 1);
        self.map.swapRemoveAt(idx);
        if (idx == last) return;
        // The former last entry now lives at `idx`; repoint its neighbours.
        const moved = self.nodes()[idx];
        if (moved.prev != none) self.nodes()[moved.prev].next = idx else self.head = idx;
        if (moved.next != none) self.nodes()[moved.next].prev = idx else self.tail = idx;
    }

    fn unlink(self: *Cache, idx: Index) void {
        const all = self.nodes();
        const node = &all[idx];
        if (node.prev != none) all[node.prev].next = node.next else self.head = node.next;
        if (node.next != none) all[node.next].prev = node.prev else self.tail = node.prev;
        node.prev = none;
        node.next = none;
    }

    fn pushFront(self: *Cache, idx: Index) void {
        const all = self.nodes();
        all[idx].prev = none;
        all[idx].next = self.head;
        if (self.head != none) all[self.head].prev = idx else self.tail = idx;
        self.head = idx;
    }
};

/// Runs the command script in `input`; keys and values borrow from it.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    const capacity = std.fmt.parseInt(usize, std.mem.trim(u8, first, " \t\r"), 10) catch return error.InvalidCapacity;

    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);
    try cache.map.ensureTotalCapacity(gpa, @min(capacity + 1, 1 << 20));

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        var tokens = std.mem.splitScalar(u8, line, ' ');
        const op = tokens.next() orelse continue;
        if (std.mem.eql(u8, op, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.set(gpa, key, value);
        } else if (std.mem.eql(u8, op, "GET")) {
            const key = tokens.next() orelse continue;
            try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
        } else if (std.mem.eql(u8, op, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, op, "SIZE")) {
            try out.print("{d}\n", .{cache.size()});
        }
    }
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectOutput("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete, size, capacity one" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
    try expectOutput("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
}

test "eviction churn keeps links consistent" {
    const gpa = std.testing.allocator;
    var cache: Cache = .init(3);
    defer cache.deinit(gpa);
    const keys = [_][]const u8{ "a", "b", "c", "d", "e" };
    for (0..200) |i| {
        const k = keys[(i * 7) % keys.len];
        switch (i % 4) {
            0, 1 => try cache.set(gpa, k, k),
            2 => _ = cache.get(k),
            else => _ = cache.del(k),
        }
        try std.testing.expect(cache.size() <= 3);
        var n: usize = 0;
        var it = cache.head;
        while (it != none) : (it = cache.nodes()[it].next) n += 1;
        try std.testing.expectEqual(cache.size(), n);
    }
}
