//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes command results to stdout. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// A least-recently-used cache mapping byte-string keys to byte-string values.
///
/// Keys and values are borrowed: the caller guarantees that they outlive the
/// cache. Entries live in a pooled array and form an intrusive doubly linked
/// list ordered from most (head) to least (tail) recently used, so every
/// operation is O(1) expected time.
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
    /// Removals since the map was last rehashed. The std hash map deletes by
    /// leaving tombstones that only an explicit rehash clears; left unchecked
    /// they degrade probe lengths to O(n) under insert/delete churn.
    tombstones: usize = 0,
    /// Head of the singly linked list of recycled nodes (linked through `next`).
    free: Index = none,
    head: Index = none,
    tail: Index = none,

    pub fn init(capacity: usize) Lru {
        std.debug.assert(capacity >= 1);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *Lru, gpa: Allocator) void {
        self.nodes.deinit(gpa);
        self.map.deinit(gpa);
        self.* = undefined;
    }

    /// Pre-sizes internal storage for up to `n` simultaneously held keys.
    pub fn reserve(self: *Lru, gpa: Allocator, n: usize) Allocator.Error!void {
        const count = std.math.cast(u32, n) orelse return error.OutOfMemory;
        try self.nodes.ensureTotalCapacity(gpa, n);
        try self.map.ensureTotalCapacity(gpa, count);
    }

    pub fn size(self: *const Lru) usize {
        return self.map.count();
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
        const idx = self.map.get(key) orelse return null;
        self.moveToFront(idx);
        return self.nodes.items[idx].value;
    }

    /// Inserts or overwrites `key`, marks it most recently used, and evicts the
    /// least recently used entry if the capacity is exceeded.
    pub fn set(self: *Lru, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            const idx = gop.value_ptr.*;
            self.nodes.items[idx].value = value;
            self.moveToFront(idx);
            return;
        }
        const idx = self.allocNode(gpa) catch |err| {
            self.map.removeByPtr(gop.key_ptr);
            return err;
        };
        gop.value_ptr.* = idx;
        self.nodes.items[idx] = .{ .key = key, .value = value, .prev = none, .next = none };
        self.pushFront(idx);

        if (self.map.count() > self.capacity) {
            const victim = self.tail;
            const removed = self.removeKey(self.nodes.items[victim].key);
            std.debug.assert(removed != null);
            self.unlink(victim);
            self.freeNode(victim);
        }
    }

    /// Removes `key`. Returns whether it was present.
    pub fn del(self: *Lru, key: []const u8) bool {
        const idx = self.removeKey(key) orelse return false;
        self.unlink(idx);
        self.freeNode(idx);
        return true;
    }

    /// Removes `key` from the map, returning its node index if present.
    /// Rehashes once tombstones reach a fixed fraction of the table, which
    /// keeps the O(capacity) rehash cost amortized O(1) per removal.
    fn removeKey(self: *Lru, key: []const u8) ?Index {
        const kv = self.map.fetchRemove(key) orelse return null;
        self.tombstones += 1;
        if (self.tombstones >= self.map.capacity() / 4) {
            self.map.rehash(std.hash_map.StringContext{});
            self.tombstones = 0;
        }
        return kv.value;
    }

    fn allocNode(self: *Lru, gpa: Allocator) Allocator.Error!Index {
        if (self.free != none) {
            const idx = self.free;
            self.free = self.nodes.items[idx].next;
            return idx;
        }
        const idx = std.math.cast(Index, self.nodes.items.len) orelse return error.OutOfMemory;
        if (idx == none) return error.OutOfMemory;
        _ = try self.nodes.addOne(gpa);
        return idx;
    }

    fn freeNode(self: *Lru, idx: Index) void {
        self.nodes.items[idx] = .{ .key = &.{}, .value = &.{}, .prev = none, .next = self.free };
        self.free = idx;
    }

    fn unlink(self: *Lru, idx: Index) void {
        const node = &self.nodes.items[idx];
        if (node.prev != none) self.nodes.items[node.prev].next = node.next else self.head = node.next;
        if (node.next != none) self.nodes.items[node.next].prev = node.prev else self.tail = node.prev;
        node.prev = none;
        node.next = none;
    }

    fn pushFront(self: *Lru, idx: Index) void {
        const node = &self.nodes.items[idx];
        node.prev = none;
        node.next = self.head;
        if (self.head != none) self.nodes.items[self.head].prev = idx else self.tail = idx;
        self.head = idx;
    }

    fn moveToFront(self: *Lru, idx: Index) void {
        if (self.head == idx) return;
        self.unlink(idx);
        self.pushFront(idx);
    }
};

const max_capacity = 1_000_000;

/// Executes the command script in `input`, writing results to `out`.
/// Keys and values are borrowed from `input`.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(lines.next() orelse return) orelse return error.InvalidCapacity;

    var cache: Lru = .init(capacity);
    defer cache.deinit(gpa);
    // Never more keys than capacity + 1 (transiently) or than SET commands.
    const max_keys = @min(capacity + 1, std.mem.count(u8, input, "\n") + 1);
    try cache.reserve(gpa, max_keys);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const cmd = tokens.next() orelse continue;
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
            try out.print("{d}\n", .{cache.size()});
        }
    }
}

fn parseCapacity(line: []const u8) ?usize {
    const text = std.mem.trim(u8, line, " \t\r");
    const c = std.fmt.parseInt(usize, text, 10) catch return null;
    if (c < 1 or c > max_capacity) return null;
    return c;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &out_buf);
    run(gpa, input, &stdout.interface) catch |err| switch (err) {
        error.InvalidCapacity => std.process.fatal("invalid capacity on line 1", .{}),
        else => |e| return e,
    };
    try stdout.interface.flush();
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var aw: Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try run(std.testing.allocator, input, &aw.writer);
    try std.testing.expectEqualStrings(expected, aw.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectRun("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "capacity one" {
    try expectRun("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
}

test "node reuse after delete and eviction" {
    try expectRun(
        "2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\nDEL d\nDEL c\nSIZE\nSET e 5\nGET e\n",
        "1\nNULL\n3\n4\n2\n1\n1\n0\n5\n",
    );
}

test "get refreshes recency" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\nGET c\n", "1\n1\nNULL\n3\n");
}
