//! Fixed-capacity LRU cache: a string hash map from key to slot, plus an
//! intrusive doubly linked list threaded through a slot array. The map is an
//! array hash map because its removals leave no tombstones, so heavy
//! insert/evict churn cannot degrade lookups. Every operation runs in O(1)
//! expected time.
//!
//! Keys and values are borrowed, not copied: the caller must keep the memory
//! they point to alive for as long as the cache holds them.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const LruCache = struct {
    const Slot = u32;
    const nil: Slot = std.math.maxInt(Slot);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        /// Towards the most recently used end; reused as the free-list link.
        prev: Slot,
        /// Towards the least recently used end.
        next: Slot,
    };

    gpa: Allocator,
    capacity: u32,
    index: std.StringArrayHashMapUnmanaged(Slot) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    /// Most recently used.
    head: Slot = nil,
    /// Least recently used.
    tail: Slot = nil,
    /// Singly linked (through `Node.next`) list of released slots.
    free: Slot = nil,

    pub fn init(gpa: Allocator, capacity: u32) LruCache {
        std.debug.assert(capacity >= 1 and capacity < nil);
        return .{ .gpa = gpa, .capacity = capacity };
    }

    pub fn deinit(self: *LruCache) void {
        self.index.deinit(self.gpa);
        self.nodes.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn count(self: *const LruCache) u32 {
        return @intCast(self.index.count());
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const slot = self.index.get(key) orelse return null;
        self.moveToFront(slot);
        return self.nodes.items[slot].value;
    }

    /// Inserts or overwrites `key`, marking it most recently used. Evicts the
    /// least recently used key if the cache would exceed its capacity.
    pub fn put(self: *LruCache, key: []const u8, value: []const u8) Allocator.Error!void {
        if (self.index.get(key)) |slot| {
            self.nodes.items[slot].value = value;
            self.moveToFront(slot);
            return;
        }
        if (self.index.count() == self.capacity) self.release(self.tail);

        const slot = try self.allocSlot();
        errdefer self.freeSlot(slot);
        try self.index.putNoClobber(self.gpa, key, slot);
        self.nodes.items[slot].key = key;
        self.nodes.items[slot].value = value;
        self.pushFront(slot);
    }

    /// Removes `key`. Returns whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const kv = self.index.fetchSwapRemove(key) orelse return false;
        self.unlink(kv.value);
        self.freeSlot(kv.value);
        return true;
    }

    fn release(self: *LruCache, slot: Slot) void {
        self.unlink(slot);
        const removed = self.index.swapRemove(self.nodes.items[slot].key);
        std.debug.assert(removed);
        self.freeSlot(slot);
    }

    fn allocSlot(self: *LruCache) Allocator.Error!Slot {
        if (self.free != nil) {
            const slot = self.free;
            self.free = self.nodes.items[slot].next;
            return slot;
        }
        const slot: Slot = @intCast(self.nodes.items.len);
        try self.nodes.append(self.gpa, undefined);
        return slot;
    }

    fn freeSlot(self: *LruCache, slot: Slot) void {
        self.nodes.items[slot] = .{ .key = &.{}, .value = &.{}, .prev = nil, .next = self.free };
        self.free = slot;
    }

    fn unlink(self: *LruCache, slot: Slot) void {
        const nodes = self.nodes.items;
        const p = nodes[slot].prev;
        const n = nodes[slot].next;
        if (p == nil) self.head = n else nodes[p].next = n;
        if (n == nil) self.tail = p else nodes[n].prev = p;
    }

    fn pushFront(self: *LruCache, slot: Slot) void {
        const nodes = self.nodes.items;
        nodes[slot].prev = nil;
        nodes[slot].next = self.head;
        if (self.head == nil) self.tail = slot else nodes[self.head].prev = slot;
        self.head = slot;
    }

    fn moveToFront(self: *LruCache, slot: Slot) void {
        if (slot == self.head) return;
        self.unlink(slot);
        self.pushFront(slot);
    }
};

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put("c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try cache.put("a", "9");
    try cache.put("c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and slot reuse" {
    var cache: LruCache = .init(testing.allocator, 1);
    defer cache.deinit();

    try cache.put("x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try cache.put("y", "2");
    try cache.put("z", "3");
    try testing.expectEqual(null, cache.get("y"));
    try testing.expectEqualStrings("3", cache.get("z").?);
    try testing.expectEqual(1, cache.nodes.items.len);
}
