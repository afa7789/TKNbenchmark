//! A least-recently-used cache mapping byte-string keys to byte-string values.
//!
//! Keys and values are borrowed slices: the caller guarantees they outlive the
//! cache. Entries live in a node pool threaded by an index-based doubly linked
//! list (head = least recently used, tail = most recently used). Keys are
//! indexed by an open-addressing hash table of node indices using linear
//! probing with backward-shift deletion. Avoiding tombstones keeps probe
//! sequences short under the heavy insert/evict/delete churn typical of a
//! cache, so every operation runs in O(1) expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Node = struct {
    key: []const u8,
    value: []const u8,
    hash: u64,
    prev: Index,
    next: Index,
};

capacity: usize,
/// Hash index: each slot holds a node index or `none`. Length is zero or a
/// power of two, and kept at most half full.
slots: []Index = &.{},
nodes: std.ArrayList(Node) = .empty,
count: usize = 0,
/// Head of a singly linked list (through `Node.next`) of reusable nodes.
free: Index = none,
head: Index = none,
tail: Index = none,

const min_slots = 16;

pub fn init(capacity: usize) LruCache {
    return .{ .capacity = capacity };
}

pub fn deinit(self: *LruCache, gpa: Allocator) void {
    gpa.free(self.slots);
    self.nodes.deinit(gpa);
    self.* = undefined;
}

/// Pre-allocates room for `n` live entries.
pub fn ensureTotalCapacity(self: *LruCache, gpa: Allocator, n: usize) Allocator.Error!void {
    if (n >= none) return error.OutOfMemory;
    try self.nodes.ensureTotalCapacity(gpa, n);
    const wanted = std.math.ceilPowerOfTwo(usize, @max(min_slots, n * 2)) catch return error.OutOfMemory;
    if (wanted > self.slots.len) try self.rehash(gpa, wanted);
}

/// Number of keys currently held.
pub fn len(self: *const LruCache) usize {
    return self.count;
}

/// Returns the value for `key` and marks it most recently used.
pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
    if (self.count == 0) return null;
    const probe = self.find(key, hashKey(key));
    if (!probe.found) return null;
    const index = self.slots[probe.slot];
    self.moveToBack(index);
    return self.nodes.items[index].value;
}

/// Inserts or overwrites `key`, making it most recently used. Evicts the least
/// recently used entry if the cache grows beyond its capacity.
pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    try self.ensureTotalCapacity(gpa, self.count + 1);
    const hash = hashKey(key);
    const probe = self.find(key, hash);
    if (probe.found) {
        const index = self.slots[probe.slot];
        self.nodes.items[index].value = value;
        self.moveToBack(index);
        return;
    }

    const index = try self.allocNode(gpa);
    self.nodes.items[index] = .{ .key = key, .value = value, .hash = hash, .prev = none, .next = none };
    self.slots[probe.slot] = index;
    self.count += 1;
    self.pushBack(index);

    if (self.count > self.capacity) {
        const lru = self.nodes.items[self.head];
        _ = self.remove(lru.key);
    }
}

/// Removes `key`. Returns whether it was present.
pub fn remove(self: *LruCache, key: []const u8) bool {
    if (self.count == 0) return false;
    const probe = self.find(key, hashKey(key));
    if (!probe.found) return false;
    const index = self.slots[probe.slot];
    self.vacate(probe.slot);
    self.count -= 1;
    self.unlink(index);
    self.releaseNode(index);
    return true;
}

fn hashKey(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key);
}

const Probe = struct { slot: usize, found: bool };

/// Locates `key`, or the empty slot where it would be inserted.
/// Requires a non-empty slot table.
fn find(self: *const LruCache, key: []const u8, hash: u64) Probe {
    const mask = self.slots.len - 1;
    var slot: usize = @intCast(hash & mask);
    while (true) : (slot = (slot + 1) & mask) {
        const index = self.slots[slot];
        if (index == none) return .{ .slot = slot, .found = false };
        const node = &self.nodes.items[index];
        if (node.hash == hash and std.mem.eql(u8, node.key, key)) return .{ .slot = slot, .found = true };
    }
}

/// Empties `slot`, shifting later members of its probe run back so that no
/// lookup is cut short by the new gap.
fn vacate(self: *LruCache, slot: usize) void {
    const mask = self.slots.len - 1;
    var hole = slot;
    var i = (slot + 1) & mask;
    while (self.slots[i] != none) : (i = (i + 1) & mask) {
        const home: usize = @intCast(self.nodes.items[self.slots[i]].hash & mask);
        // The entry may fill the hole only if the hole lies on its probe path.
        if (((i -% home) & mask) >= ((i -% hole) & mask)) {
            self.slots[hole] = self.slots[i];
            hole = i;
        }
    }
    self.slots[hole] = none;
}

fn rehash(self: *LruCache, gpa: Allocator, slot_count: usize) Allocator.Error!void {
    const slots = try gpa.alloc(Index, slot_count);
    @memset(slots, none);
    gpa.free(self.slots);
    self.slots = slots;
    const mask = slot_count - 1;
    var index = self.head;
    while (index != none) : (index = self.nodes.items[index].next) {
        var slot: usize = @intCast(self.nodes.items[index].hash & mask);
        while (slots[slot] != none) slot = (slot + 1) & mask;
        slots[slot] = index;
    }
}

fn allocNode(self: *LruCache, gpa: Allocator) Allocator.Error!Index {
    if (self.free != none) {
        const index = self.free;
        self.free = self.nodes.items[index].next;
        return index;
    }
    const index = std.math.cast(Index, self.nodes.items.len) orelse return error.OutOfMemory;
    if (index == none) return error.OutOfMemory;
    _ = try self.nodes.addOne(gpa);
    return index;
}

fn releaseNode(self: *LruCache, index: Index) void {
    self.nodes.items[index] = .{ .key = &.{}, .value = &.{}, .hash = 0, .prev = none, .next = self.free };
    self.free = index;
}

fn pushBack(self: *LruCache, index: Index) void {
    const node = &self.nodes.items[index];
    node.prev = self.tail;
    node.next = none;
    if (self.tail != none) {
        self.nodes.items[self.tail].next = index;
    } else {
        self.head = index;
    }
    self.tail = index;
}

fn unlink(self: *LruCache, index: Index) void {
    const node = self.nodes.items[index];
    if (node.prev != none) {
        self.nodes.items[node.prev].next = node.next;
    } else {
        self.head = node.next;
    }
    if (node.next != none) {
        self.nodes.items[node.next].prev = node.prev;
    } else {
        self.tail = node.prev;
    }
}

fn moveToBack(self: *LruCache, index: Index) void {
    if (index == self.tail) return;
    self.unlink(index);
    self.pushBack(index);
}

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expect(cache.get("b") == null);
    try testing.expectEqual(2, cache.len());
}

test "overwrite refreshes recency" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expect(cache.get("b") == null);
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and node reuse" {
    var cache: LruCache = .init(1);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.len());
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expect(cache.get("a") == null);
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.len());
    try testing.expect(cache.nodes.items.len <= 2);
}

test "randomized against a reference model" {
    const gpa = testing.allocator;
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();

    var names: [64][4]u8 = undefined;
    for (&names, 0..) |*name, i| _ = std.fmt.bufPrint(name, "k{d:0>3}", .{i}) catch unreachable;

    const capacity = 16;
    var cache: LruCache = .init(capacity);
    defer cache.deinit(gpa);
    // Reference: keys ordered from least to most recently used.
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(gpa);
    var values: [64][]const u8 = undefined;
    const value_pool = [_][]const u8{ "a", "b", "c", "d" };

    for (0..20_000) |_| {
        const k = random.uintLessThan(usize, names.len);
        const key: []const u8 = &names[k];
        const pos = std.mem.indexOfScalar(usize, order.items, k);
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const v = value_pool[random.uintLessThan(usize, value_pool.len)];
                try cache.put(gpa, key, v);
                if (pos) |p| _ = order.orderedRemove(p);
                try order.append(gpa, k);
                values[k] = v;
                if (order.items.len > capacity) _ = order.orderedRemove(0);
            },
            1 => {
                const got = cache.get(key);
                if (pos) |p| {
                    try testing.expectEqualStrings(values[k], got.?);
                    _ = order.orderedRemove(p);
                    try order.append(gpa, k);
                } else try testing.expect(got == null);
            },
            else => {
                try testing.expectEqual(pos != null, cache.remove(key));
                if (pos) |p| _ = order.orderedRemove(p);
            },
        }
        try testing.expectEqual(order.items.len, cache.len());
    }
}
