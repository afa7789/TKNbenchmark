//! LRU cache simulator.
//!
//! Reads a capacity followed by `SET`/`GET`/`DEL`/`SIZE` commands from stdin
//! and writes one line of output per `GET`, `DEL` and `SIZE` command.
//!
//! The whole input is read into memory up front; keys and values stored in
//! the cache are slices into that buffer, so no per-entry copies are made.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// A least-recently-used cache mapping byte-string keys to byte-string values.
///
/// Entries live in a pool of nodes linked into a circular doubly-linked list
/// through a sentinel at index 0: `sentinel.next` is the most recently used
/// entry and `sentinel.prev` the least recently used. A hash map indexes the
/// nodes by key, so every operation runs in O(1) expected time.
///
/// The cache does not own key or value memory; callers must keep the slices
/// alive for as long as they may be stored.
pub const LruCache = struct {
    const Index = u32;
    const sentinel: Index = 0;

    const Node = struct {
        key: []const u8,
        value: []const u8,
        prev: Index,
        next: Index,
    };

    capacity: usize,
    nodes: std.ArrayList(Node),
    /// Head of a singly-linked list (through `Node.next`) of reusable nodes.
    free_head: ?Index,
    /// An array hash map is used rather than an open-addressing map with
    /// tombstones: heavy insert/remove churn would otherwise fill the table
    /// with tombstones and degrade lookups of absent keys.
    map: std.StringArrayHashMapUnmanaged(Index),

    pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!LruCache {
        std.debug.assert(capacity >= 1);
        std.debug.assert(capacity < std.math.maxInt(Index));
        var nodes: std.ArrayList(Node) = .empty;
        try nodes.append(gpa, .{ .key = "", .value = "", .prev = sentinel, .next = sentinel });
        return .{ .capacity = capacity, .nodes = nodes, .free_head = null, .map = .empty };
    }

    pub fn deinit(self: *LruCache, gpa: Allocator) void {
        self.nodes.deinit(gpa);
        self.map.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const LruCache) usize {
        return self.map.count();
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const index = self.map.get(key) orelse return null;
        self.moveToFront(index);
        return self.nodes.items[index].value;
    }

    /// Inserts or overwrites `key`, marking it most recently used and evicting
    /// the least recently used entry if the capacity is exceeded.
    pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        // Reserve a node slot first so nothing can fail after the map insert.
        try self.nodes.ensureUnusedCapacity(gpa, 1);
        const gop = try self.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            const index = gop.value_ptr.*;
            self.nodes.items[index].value = value;
            self.moveToFront(index);
            return;
        }

        const index = if (self.map.count() > self.capacity) blk: {
            // Over capacity: evict the least recently used entry and recycle
            // its node, so the pool never exceeds `capacity` live nodes.
            // The new entry's value must be written before the swap-remove,
            // which may move it and invalidate `gop.value_ptr`.
            const lru = self.nodes.items[sentinel].prev;
            std.debug.assert(lru != sentinel);
            gop.value_ptr.* = lru;
            const removed = self.map.swapRemove(self.nodes.items[lru].key);
            std.debug.assert(removed);
            self.unlink(lru);
            break :blk lru;
        } else blk: {
            const index = self.allocNode();
            gop.value_ptr.* = index;
            break :blk index;
        };
        self.nodes.items[index] = .{ .key = key, .value = value, .prev = sentinel, .next = sentinel };
        self.linkFront(index);
    }

    /// Removes `key`, returning whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const kv = self.map.fetchSwapRemove(key) orelse return false;
        self.unlink(kv.value);
        self.freeNode(kv.value);
        return true;
    }

    /// Returns a node index from the free list, or appends a new node.
    /// Asserts that the pool has spare capacity when the free list is empty.
    fn allocNode(self: *LruCache) Index {
        if (self.free_head) |index| {
            const next = self.nodes.items[index].next;
            self.free_head = if (next == sentinel) null else next;
            return index;
        }
        const index: Index = @intCast(self.nodes.items.len);
        _ = self.nodes.addOneAssumeCapacity();
        return index;
    }

    fn freeNode(self: *LruCache, index: Index) void {
        self.nodes.items[index] = .{
            .key = "",
            .value = "",
            .prev = sentinel,
            .next = self.free_head orelse sentinel,
        };
        self.free_head = index;
    }

    fn unlink(self: *LruCache, index: Index) void {
        const nodes = self.nodes.items;
        const node = nodes[index];
        nodes[node.prev].next = node.next;
        nodes[node.next].prev = node.prev;
    }

    fn linkFront(self: *LruCache, index: Index) void {
        const nodes = self.nodes.items;
        const first = nodes[sentinel].next;
        nodes[index].prev = sentinel;
        nodes[index].next = first;
        nodes[first].prev = index;
        nodes[sentinel].next = index;
    }

    fn moveToFront(self: *LruCache, index: Index) void {
        if (self.nodes.items[sentinel].next == index) return;
        self.unlink(index);
        self.linkFront(index);
    }
};

const max_capacity = 1_000_000;

/// Executes every command in `input` against a fresh cache, writing results to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');

    const capacity = while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        break std.fmt.parseInt(usize, line, 10) catch return error.InvalidCapacity;
    } else return; // empty input: nothing to do
    if (capacity < 1 or capacity > max_capacity) return error.InvalidCapacity;

    var cache: LruCache = try .init(gpa, capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const command = tokens.next() orelse continue;

        if (std.mem.eql(u8, command, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.put(gpa, key, value);
        } else if (std.mem.eql(u8, command, "GET")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(cache.get(key) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, command, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.remove(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, command, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    try run(gpa, input, &stdout.interface);
    try stdout.interface.flush();
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
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

test "node reuse after delete and eviction" {
    const gpa = std.testing.allocator;
    var cache: LruCache = try .init(gpa, 2);
    defer cache.deinit(gpa);

    try cache.put(gpa, "a", "1");
    try cache.put(gpa, "b", "2");
    try std.testing.expect(cache.remove("a"));
    try cache.put(gpa, "c", "3");
    try cache.put(gpa, "d", "4"); // evicts b
    try std.testing.expectEqual(null, cache.get("b"));
    try std.testing.expectEqualStrings("3", cache.get("c").?);
    try cache.put(gpa, "e", "5"); // evicts d
    try std.testing.expectEqual(null, cache.get("d"));
    try std.testing.expectEqual(2, cache.count());
    try std.testing.expectEqual(3, cache.nodes.items.len); // sentinel + 2
}
