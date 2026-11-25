//! LRU cache simulator: reads a capacity and a command stream from stdin,
//! writes command results to stdout. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// A string-keyed LRU cache. Keys and values are borrowed slices; the caller
/// must keep their backing memory alive for the lifetime of the cache.
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
    map: std.StringHashMapUnmanaged(Index) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    /// Head of the free-node list, threaded through `Node.next`.
    free: Index = none,
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,

    pub fn init(capacity: usize) Lru {
        std.debug.assert(capacity >= 1);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *Lru, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.nodes.deinit(gpa);
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
        const idx = self.allocNode(gpa) catch |err| {
            self.map.removeByPtr(gop.key_ptr);
            return err;
        };
        gop.value_ptr.* = idx;
        self.nodes.items[idx] = .{ .key = key, .value = value, .prev = none, .next = none };
        self.pushFront(idx);

        if (self.map.count() > self.capacity) {
            const lru = self.tail;
            self.unlink(lru);
            const removed = self.map.remove(self.nodes.items[lru].key);
            std.debug.assert(removed);
            self.releaseNode(lru);
        }
    }

    /// Returns true if the key was present.
    pub fn del(self: *Lru, key: []const u8) bool {
        const kv = self.map.fetchRemove(key) orelse return false;
        self.unlink(kv.value);
        self.releaseNode(kv.value);
        return true;
    }

    fn allocNode(self: *Lru, gpa: Allocator) Allocator.Error!Index {
        if (self.free != none) {
            const idx = self.free;
            self.free = self.nodes.items[idx].next;
            return idx;
        }
        const idx: Index = @intCast(self.nodes.items.len);
        _ = try self.nodes.addOne(gpa);
        return idx;
    }

    fn releaseNode(self: *Lru, idx: Index) void {
        self.nodes.items[idx].next = self.free;
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

/// Executes every command in `input` against a fresh cache, writing results to `out`.
/// Malformed or unknown command lines are ignored.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    const capacity = std.fmt.parseInt(usize, trimLine(first), 10) catch return error.InvalidCapacity;
    if (capacity == 0) return error.InvalidCapacity;

    var cache: Lru = .init(capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        var tokens = std.mem.tokenizeScalar(u8, trimLine(raw), ' ');
        const cmd = tokens.next() orelse continue;
        if (std.mem.eql(u8, cmd, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.set(gpa, key, value);
        } else if (std.mem.eql(u8, cmd, "GET")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(cache.get(key) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var in = Io.File.stdin().reader(io, &in_buf);
    const input = try in.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var out = Io.File.stdout().writer(io, &out_buf);
    run(gpa, input, &out.interface) catch |err| switch (err) {
        error.InvalidCapacity => std.process.fatal("invalid capacity line", .{}),
        else => |e| return e,
    };
    try out.interface.flush();
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
    try expectRun("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one and node reuse" {
    try expectRun("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\nDEL b\nSET c 3\nSET d 4\nGET c\nGET d\n", "NULL\n2\n1\n1\nNULL\n4\n");
}

test "get refreshes recency" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET a\nGET b\nGET c\n", "1\n1\nNULL\n3\n");
}
