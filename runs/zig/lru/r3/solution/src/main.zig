//! LRU cache simulator: reads a capacity and a stream of commands from stdin,
//! writes command results to stdout. See SPEC.md.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Fixed-capacity LRU cache mapping byte-string keys to byte-string values.
///
/// Keys and values are borrowed slices; the caller must keep them alive for
/// as long as the cache may reference them. Recency is tracked by an
/// intrusive doubly linked list over a node pool addressed by `u32` indices,
/// so every operation is O(1) expected time.
pub const Lru = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        prev: Index,
        next: Index,
    };

    gpa: Allocator,
    capacity: usize,
    map: std.StringHashMapUnmanaged(Index) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    /// Head of the singly linked free list (threaded through `Node.next`).
    free: Index = none,
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,

    pub fn init(gpa: Allocator, capacity: usize) Lru {
        std.debug.assert(capacity >= 1);
        return .{ .gpa = gpa, .capacity = capacity };
    }

    pub fn deinit(self: *Lru) void {
        self.map.deinit(self.gpa);
        self.nodes.deinit(self.gpa);
        self.* = undefined;
    }

    /// Pre-allocates room for `n` live entries.
    pub fn reserve(self: *Lru, n: usize) Allocator.Error!void {
        const count: u32 = @intCast(@min(n, std.math.maxInt(u32)));
        try self.map.ensureTotalCapacity(self.gpa, count);
        try self.nodes.ensureTotalCapacity(self.gpa, count);
    }

    pub fn len(self: *const Lru) usize {
        return self.map.count();
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
        const idx = self.map.get(key) orelse return null;
        self.moveToFront(idx);
        return self.nodes.items[idx].value;
    }

    /// Inserts or overwrites `key`, marking it most recently used and
    /// evicting the least recently used entry if over capacity.
    pub fn set(self: *Lru, key: []const u8, value: []const u8) Allocator.Error!void {
        // Make sure a node slot exists before touching the map so a failed
        // allocation leaves the cache unchanged.
        if (self.free == none) try self.nodes.ensureUnusedCapacity(self.gpa, 1);
        const gop = try self.map.getOrPut(self.gpa, key);
        if (gop.found_existing) {
            const idx = gop.value_ptr.*;
            self.nodes.items[idx].value = value;
            self.moveToFront(idx);
            return;
        }

        const idx = self.allocNode();
        self.nodes.items[idx] = .{ .key = key, .value = value, .prev = none, .next = none };
        gop.value_ptr.* = idx;
        self.pushFront(idx);

        if (self.map.count() > self.capacity) {
            const lru = self.tail;
            const removed = self.map.remove(self.nodes.items[lru].key);
            std.debug.assert(removed);
            self.unlink(lru);
            self.freeNode(lru);
        }
    }

    /// Removes `key`; returns whether it was present.
    pub fn del(self: *Lru, key: []const u8) bool {
        const kv = self.map.fetchRemove(key) orelse return false;
        self.unlink(kv.value);
        self.freeNode(kv.value);
        return true;
    }

    fn allocNode(self: *Lru) Index {
        if (self.free != none) {
            const idx = self.free;
            self.free = self.nodes.items[idx].next;
            return idx;
        }
        const idx: Index = @intCast(self.nodes.items.len);
        _ = self.nodes.addOneAssumeCapacity();
        return idx;
    }

    fn freeNode(self: *Lru, idx: Index) void {
        self.nodes.items[idx] = .{ .key = &.{}, .value = &.{}, .prev = none, .next = self.free };
        self.free = idx;
    }

    fn pushFront(self: *Lru, idx: Index) void {
        const n = &self.nodes.items[idx];
        n.prev = none;
        n.next = self.head;
        if (self.head != none) self.nodes.items[self.head].prev = idx else self.tail = idx;
        self.head = idx;
    }

    fn unlink(self: *Lru, idx: Index) void {
        const n = self.nodes.items[idx];
        if (n.prev != none) self.nodes.items[n.prev].next = n.next else self.head = n.next;
        if (n.next != none) self.nodes.items[n.next].prev = n.prev else self.tail = n.prev;
    }

    fn moveToFront(self: *Lru, idx: Index) void {
        if (self.head == idx) return;
        self.unlink(idx);
        self.pushFront(idx);
    }
};

const max_capacity = 1_000_000;

/// Executes every command in `input` (capacity line first) and writes the
/// results to `out`. Slices of `input` are stored in the cache, so it must
/// outlive the call.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    const capacity = std.fmt.parseUnsigned(usize, std.mem.trim(u8, first, " \t\r"), 10) catch
        return error.InvalidCapacity;
    if (capacity < 1 or capacity > max_capacity) return error.InvalidCapacity;

    var cache: Lru = .init(gpa, capacity);
    defer cache.deinit();
    // The number of live keys never exceeds capacity + 1 nor the number of
    // commands, so sizing up front avoids rehashing during the run.
    try cache.reserve(@min(capacity + 1, std.mem.count(u8, input, "\n") + 1));

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
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
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.len()});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

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

test "delete and reuse slots" {
    try expectRun("1\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\nSET y 2\nSET z 3\nGET y\nGET z\nSIZE\n", "1\n0\n0\nNULL\nNULL\n3\n1\n");
}

test "delete tail and head keeps list consistent" {
    try expectRun("3\nSET a 1\nSET b 2\nSET c 3\nDEL a\nDEL c\nSET d 4\nSET e 5\nGET b\nGET d\nGET e\nSIZE\n", "1\n1\n2\n4\n5\n3\n");
}
