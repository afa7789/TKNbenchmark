//! LRU cache simulator: reads a capacity and a stream of SET/GET/DEL/SIZE
//! commands from stdin and writes command results to stdout.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Fixed-capacity LRU cache mapping byte-string keys to byte-string values.
/// Keys and values are borrowed slices; the caller keeps them alive.
/// All operations run in O(1) expected time.
pub const Lru = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        prev: Index,
        next: Index,
    };

    capacity: usize,
    nodes: std.ArrayList(Node) = .empty,
    map: std.StringHashMapUnmanaged(Index) = .empty,
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,
    /// Singly linked (via `next`) list of recycled node slots.
    free: Index = none,
    /// Removals since the map was last rehashed. `std.HashMapUnmanaged`
    /// deletes with tombstones that are never reclaimed by insertion alone;
    /// left unchecked they eliminate free slots and turn misses into full
    /// table scans. Rehashing every `capacity / 4` removals keeps probes short
    /// at amortized O(1) cost.
    removals: usize = 0,

    pub fn init(gpa: Allocator, capacity: usize, expected_keys: usize) Allocator.Error!Lru {
        std.debug.assert(capacity >= 1);
        var self: Lru = .{ .capacity = capacity };
        errdefer self.deinit(gpa);
        const reserve: Index = @intCast(@min(capacity, expected_keys) + 1);
        try self.nodes.ensureTotalCapacity(gpa, reserve);
        // Keep the live load at or below ~50% so tombstones have headroom.
        try self.map.ensureTotalCapacity(gpa, reserve * 2);
        return self;
    }

    pub fn deinit(self: *Lru, gpa: Allocator) void {
        self.nodes.deinit(gpa);
        self.map.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Lru) usize {
        return self.map.count();
    }

    pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
        const idx = self.map.get(key) orelse return null;
        self.moveToFront(idx);
        return self.nodes.items[idx].value;
    }

    pub fn set(self: *Lru, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            const idx = gop.value_ptr.*;
            self.nodes.items[idx].value = value;
            self.moveToFront(idx);
            return;
        }
        errdefer _ = self.map.remove(key);
        const idx = try self.allocNode(gpa, .{ .key = key, .value = value, .prev = none, .next = none });
        gop.value_ptr.* = idx;
        self.pushFront(idx);
        if (self.map.count() > self.capacity) self.evict();
    }

    /// Returns whether the key was present.
    pub fn del(self: *Lru, key: []const u8) bool {
        const kv = self.map.fetchRemove(key) orelse return false;
        self.noteRemoval();
        self.unlink(kv.value);
        self.releaseNode(kv.value);
        return true;
    }

    fn evict(self: *Lru) void {
        const idx = self.tail;
        std.debug.assert(idx != none);
        const removed = self.map.remove(self.nodes.items[idx].key);
        std.debug.assert(removed);
        self.noteRemoval();
        self.unlink(idx);
        self.releaseNode(idx);
    }

    fn noteRemoval(self: *Lru) void {
        self.removals += 1;
        if (self.removals >= self.map.capacity() / 4) {
            self.map.rehash(std.hash_map.StringContext{});
            self.removals = 0;
        }
    }

    fn allocNode(self: *Lru, gpa: Allocator, node: Node) Allocator.Error!Index {
        if (self.free != none) {
            const idx = self.free;
            self.free = self.nodes.items[idx].next;
            self.nodes.items[idx] = node;
            return idx;
        }
        const idx: Index = @intCast(self.nodes.items.len);
        try self.nodes.append(gpa, node);
        return idx;
    }

    fn releaseNode(self: *Lru, idx: Index) void {
        self.nodes.items[idx] = .{ .key = &.{}, .value = &.{}, .prev = none, .next = self.free };
        self.free = idx;
    }

    fn unlink(self: *Lru, idx: Index) void {
        const n = &self.nodes.items[idx];
        if (n.prev != none) self.nodes.items[n.prev].next = n.next else self.head = n.next;
        if (n.next != none) self.nodes.items[n.next].prev = n.prev else self.tail = n.prev;
        n.prev = none;
        n.next = none;
    }

    fn pushFront(self: *Lru, idx: Index) void {
        const n = &self.nodes.items[idx];
        n.prev = none;
        n.next = self.head;
        if (self.head != none) self.nodes.items[self.head].prev = idx else self.tail = idx;
        self.head = idx;
    }

    fn moveToFront(self: *Lru, idx: Index) void {
        if (self.head == idx) return;
        self.unlink(idx);
        self.pushFront(idx);
    }
};

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

/// Executes every command in `input` and writes results to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = std.mem.trim(u8, lines.first(), " \t\r");
    const capacity = std.fmt.parseInt(usize, first, 10) catch return error.InvalidCapacity;
    if (capacity == 0) return error.InvalidCapacity;

    const expected_keys = std.mem.count(u8, input, "\n") + 1;
    var cache = try Lru.init(gpa, capacity, expected_keys);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = trimLine(raw);
        if (line.len == 0) continue;
        var tokens = std.mem.splitScalar(u8, line, ' ');
        const cmd = tokens.first();
        if (std.mem.eql(u8, cmd, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.set(gpa, key, value);
        } else if (std.mem.eql(u8, cmd, "GET")) {
            const key = tokens.next() orelse continue;
            try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = std.Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &out_buf);
    try run(gpa, input, &stdout.interface);
    try stdout.interface.flush();
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

test "capacity one and slot reuse" {
    try expectRun("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\nDEL b\nSET c 3\nSIZE\nGET c\n", "NULL\n2\n1\n1\n1\n3\n");
}
