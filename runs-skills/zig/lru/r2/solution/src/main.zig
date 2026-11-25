//! LRU cache simulator: reads a capacity and a stream of SET/GET/DEL/SIZE
//! commands from stdin and writes command results to stdout.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Index = u32;
const none: Index = std.math.maxInt(Index);

fn hashKey(key: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, key));
}

/// Open-addressing hash index from key to node index. Uses linear probing with
/// backward-shift deletion, so heavy insert/remove churn never accumulates
/// tombstones and probe lengths stay bounded by the load factor.
const KeyIndex = struct {
    const Slot = struct {
        hash: u32,
        node: Index,

        const empty: Slot = .{ .hash = 0, .node = none };
    };

    slots: []Slot = &.{},
    len: usize = 0,

    fn deinit(self: *KeyIndex, gpa: Allocator) void {
        gpa.free(self.slots);
        self.* = undefined;
    }

    inline fn mask(self: *const KeyIndex) usize {
        return self.slots.len - 1;
    }

    /// Returns the slot position holding `key`, or null.
    fn find(self: *const KeyIndex, nodes: []const Node, key: []const u8, hash: u32) ?usize {
        if (self.slots.len == 0) return null;
        var i: usize = hash & self.mask();
        while (true) : (i = (i + 1) & self.mask()) {
            const s = self.slots[i];
            if (s.node == none) return null;
            if (s.hash == hash and std.mem.eql(u8, nodes[s.node].key, key)) return i;
        }
    }

    /// Inserts a key known to be absent. Capacity must have been ensured.
    fn insertAssumeCapacity(self: *KeyIndex, hash: u32, node: Index) void {
        std.debug.assert(self.len * 2 < self.slots.len);
        var i: usize = hash & self.mask();
        while (self.slots[i].node != none) i = (i + 1) & self.mask();
        self.slots[i] = .{ .hash = hash, .node = node };
        self.len += 1;
    }

    /// Ensures room for one more entry at a load factor of at most 1/2.
    fn ensureUnusedCapacity(self: *KeyIndex, gpa: Allocator) Allocator.Error!void {
        if ((self.len + 1) * 2 <= self.slots.len) return;
        const new_len = @max(16, self.slots.len * 2);
        const old = self.slots;
        self.slots = try gpa.alloc(Slot, new_len);
        @memset(self.slots, .empty);
        self.len = 0;
        for (old) |s| if (s.node != none) self.insertAssumeCapacity(s.hash, s.node);
        gpa.free(old);
    }

    fn removeAt(self: *KeyIndex, pos: usize) void {
        const m = self.mask();
        var hole = pos;
        var i = (pos + 1) & m;
        while (self.slots[i].node != none) : (i = (i + 1) & m) {
            const home = self.slots[i].hash & m;
            // Move the entry back into the hole unless its home lies in (hole, i].
            if (((i -% home) & m) >= ((i -% hole) & m)) {
                self.slots[hole] = self.slots[i];
                hole = i;
            }
        }
        self.slots[hole] = .empty;
        self.len -= 1;
    }
};

const Node = struct {
    key: []const u8,
    value: []const u8,
    hash: u32,
    prev: Index,
    next: Index,
};

/// Fixed-capacity LRU cache over borrowed byte slices. Keys and values are not
/// copied; the caller must keep them alive for the lifetime of the cache.
pub const Lru = struct {
    capacity: usize,
    nodes: std.ArrayList(Node) = .empty,
    index: KeyIndex = .{},
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,
    /// Singly linked (through `next`) list of node slots freed by `del`.
    free: Index = none,

    pub fn init(capacity: usize) Lru {
        std.debug.assert(capacity >= 1 and capacity < none);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *Lru, gpa: Allocator) void {
        self.nodes.deinit(gpa);
        self.index.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Lru) usize {
        return self.index.len;
    }

    pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
        const pos = self.index.find(self.nodes.items, key, hashKey(key)) orelse return null;
        const idx = self.index.slots[pos].node;
        self.touch(idx);
        return self.nodes.items[idx].value;
    }

    pub fn set(self: *Lru, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const hash = hashKey(key);
        if (self.index.find(self.nodes.items, key, hash)) |pos| {
            const idx = self.index.slots[pos].node;
            self.nodes.items[idx].value = value;
            self.touch(idx);
            return;
        }

        const idx = if (self.index.len == self.capacity) self.evict() else try self.allocNode(gpa);
        errdefer self.releaseNode(idx);
        try self.index.ensureUnusedCapacity(gpa);
        self.index.insertAssumeCapacity(hash, idx);
        self.nodes.items[idx] = .{ .key = key, .value = value, .hash = hash, .prev = none, .next = none };
        self.pushFront(idx);
    }

    pub fn del(self: *Lru, key: []const u8) bool {
        const pos = self.index.find(self.nodes.items, key, hashKey(key)) orelse return false;
        const idx = self.index.slots[pos].node;
        self.index.removeAt(pos);
        self.unlink(idx);
        self.releaseNode(idx);
        return true;
    }

    /// Drops the least recently used entry and returns its now-unused node slot.
    fn evict(self: *Lru) Index {
        const victim = self.tail;
        const n = self.nodes.items[victim];
        const pos = self.index.find(self.nodes.items, n.key, n.hash).?;
        self.index.removeAt(pos);
        self.unlink(victim);
        return victim;
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

    fn touch(self: *Lru, idx: Index) void {
        if (self.head == idx) return;
        self.unlink(idx);
        self.pushFront(idx);
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
};

/// Executes every command in `input` against a fresh cache, writing results to `out`.
/// Blank or unrecognized lines are ignored.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = std.mem.trim(u8, lines.first(), " \t\r");
    const capacity = std.fmt.parseInt(u32, first, 10) catch return error.InvalidCapacity;
    if (capacity == 0) return error.InvalidCapacity;

    var cache: Lru = .init(capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
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
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var in: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const input = try in.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var out: Io.File.Writer = .init(.stdout(), io, &out_buf);
    run(gpa, input, &out.interface) catch |err| switch (err) {
        error.InvalidCapacity => std.process.fatal("invalid capacity on line 1", .{}),
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

test "delete and slot reuse" {
    try expectRun("2\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\n0\n0\nNULL\n1\nNULL\n3\n4\n2\n");
}

test "capacity one" {
    try expectRun("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
}

test "randomized against naive reference" {
    const gpa = std.testing.allocator;
    var prng: std.Random.DefaultPrng = .init(0x5eed);
    const rand = prng.random();
    const keys = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l" };
    const values = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7" };

    for ([_]usize{ 1, 2, 3, 5, 8, 16 }) |capacity| {
        var cache: Lru = .init(capacity);
        defer cache.deinit(gpa);
        // Reference: entries ordered least to most recently used.
        var model: std.ArrayList(struct { k: []const u8, v: []const u8 }) = .empty;
        defer model.deinit(gpa);

        for (0..20_000) |_| {
            const key = keys[rand.uintLessThan(usize, keys.len)];
            const pos: ?usize = for (model.items, 0..) |e, i| {
                if (std.mem.eql(u8, e.k, key)) break i;
            } else null;
            switch (rand.uintLessThan(u8, 3)) {
                0 => {
                    const value = values[rand.uintLessThan(usize, values.len)];
                    try cache.set(gpa, key, value);
                    if (pos) |p| _ = model.orderedRemove(p);
                    try model.append(gpa, .{ .k = key, .v = value });
                    if (model.items.len > capacity) _ = model.orderedRemove(0);
                },
                1 => {
                    const got = cache.get(key);
                    if (pos) |p| {
                        const e = model.orderedRemove(p);
                        try model.append(gpa, e);
                        try std.testing.expectEqualStrings(e.v, got.?);
                    } else try std.testing.expectEqual(null, got);
                },
                else => {
                    try std.testing.expectEqual(pos != null, cache.del(key));
                    if (pos) |p| _ = model.orderedRemove(p);
                },
            }
            try std.testing.expectEqual(model.items.len, cache.count());
        }
    }
}
