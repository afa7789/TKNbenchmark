//! LRU cache simulator. Keys and values are slices into the input buffer,
//! so commands never copy strings; every command runs in O(1) expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Node = struct {
    key: []const u8,
    value: []const u8,
    /// Neighbour towards the most recently used end.
    prev: Index,
    /// Neighbour towards the least recently used end.
    next: Index,
};

pub const Cache = struct {
    capacity: usize,
    nodes: std.ArrayList(Node) = .empty,
    /// Slots of deleted nodes, reused before growing `nodes`.
    free: std.ArrayList(Index) = .empty,
    map: std.StringHashMapUnmanaged(Index) = .empty,
    head: Index = none,
    tail: Index = none,

    pub fn init(capacity: usize) Cache {
        std.debug.assert(capacity >= 1);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *Cache, gpa: Allocator) void {
        self.nodes.deinit(gpa);
        self.free.deinit(gpa);
        self.map.deinit(gpa);
        self.* = undefined;
    }

    pub fn size(self: *const Cache) usize {
        return self.map.count();
    }

    pub fn get(self: *Cache, key: []const u8) ?[]const u8 {
        const index = self.map.get(key) orelse return null;
        self.moveToFront(index);
        return self.nodes.items[index].value;
    }

    pub fn set(self: *Cache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            const index = gop.value_ptr.*;
            self.nodes.items[index].value = value;
            self.moveToFront(index);
            return;
        }
        // Reserve the node slot before mutating the list so failure leaves no dangling entry.
        const index = self.allocNode(gpa) catch |err| {
            self.map.removeByPtr(gop.key_ptr);
            return err;
        };
        gop.value_ptr.* = index;
        self.nodes.items[index] = .{ .key = key, .value = value, .prev = none, .next = none };
        self.pushFront(index);
        if (self.map.count() > self.capacity) self.evict();
    }

    pub fn del(self: *Cache, key: []const u8) bool {
        const kv = self.map.fetchRemove(key) orelse return false;
        self.unlink(kv.value);
        // Capacity was reserved when the node was allocated.
        self.free.appendAssumeCapacity(kv.value);
        return true;
    }

    fn allocNode(self: *Cache, gpa: Allocator) Allocator.Error!Index {
        if (self.free.pop()) |index| return index;
        // Keep `free` large enough to hold every node, so `del` never allocates.
        try self.free.ensureTotalCapacity(gpa, self.nodes.items.len + 1);
        const index: Index = @intCast(self.nodes.items.len);
        _ = try self.nodes.addOne(gpa);
        return index;
    }

    fn evict(self: *Cache) void {
        const index = self.tail;
        std.debug.assert(index != none);
        const removed = self.map.remove(self.nodes.items[index].key);
        std.debug.assert(removed);
        self.unlink(index);
        self.free.appendAssumeCapacity(index);
    }

    fn moveToFront(self: *Cache, index: Index) void {
        if (self.head == index) return;
        self.unlink(index);
        self.pushFront(index);
    }

    fn pushFront(self: *Cache, index: Index) void {
        const node = &self.nodes.items[index];
        node.prev = none;
        node.next = self.head;
        if (self.head != none) self.nodes.items[self.head].prev = index else self.tail = index;
        self.head = index;
    }

    fn unlink(self: *Cache, index: Index) void {
        const node = self.nodes.items[index];
        if (node.prev != none) self.nodes.items[node.prev].next = node.next else self.head = node.next;
        if (node.next != none) self.nodes.items[node.next].prev = node.prev else self.tail = node.prev;
    }
};

/// Runs the command script in `input`, writing one line per producing command.
/// Malformed or unknown command lines are ignored.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = lines.next() orelse return;
    const capacity = std.fmt.parseInt(usize, trimLine(first), 10) catch return;
    if (capacity == 0) return;

    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        var tokens = std.mem.tokenizeScalar(u8, trimLine(raw), ' ');
        const op = tokens.next() orelse continue;
        const a = tokens.next();
        const b = tokens.next();
        if (tokens.next() != null) continue;

        if (std.mem.eql(u8, op, "SET")) {
            try cache.set(gpa, a orelse continue, b orelse continue);
        } else if (b != null) {
            continue;
        } else if (std.mem.eql(u8, op, "GET")) {
            try out.print("{s}\n", .{cache.get(a orelse continue) orelse "NULL"});
        } else if (std.mem.eql(u8, op, "DEL")) {
            try out.writeAll(if (cache.del(a orelse continue)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, op, "SIZE")) {
            if (a != null) continue;
            try out.print("{d}\n", .{cache.size()});
        }
    }
}

fn trimLine(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
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

test "delete and size" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one and slot reuse" {
    try expectOutput("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
    try expectOutput("2\nSET a 1\nDEL a\nSET b 2\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n");
}
