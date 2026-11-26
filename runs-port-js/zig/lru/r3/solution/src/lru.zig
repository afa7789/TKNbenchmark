//! Fixed-capacity LRU cache keyed by byte strings.
//!
//! Entries live in a slot array threaded by an intrusive doubly linked list
//! (most recently used at `head`), and a hash map translates keys to slots.
//! Every operation runs in O(1) expected time.
//!
//! Keys and values are borrowed: the cache stores the slices it is given and
//! never copies them, so the caller must keep the backing memory alive for as
//! long as the cache is in use.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const LruCache = struct {
    capacity: u32,
    /// Key -> slot index. The array hash map deletes with backward shifting,
    /// so heavy insert/delete churn leaves no tombstones behind.
    index: std.StringArrayHashMapUnmanaged(Slot) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    head: Slot = nil,
    tail: Slot = nil,
    /// Singly linked (through `Node.next`) list of recycled slots.
    free: Slot = nil,

    const Slot = u32;
    const nil = std.math.maxInt(Slot);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        prev: Slot,
        next: Slot,
    };

    pub const max_capacity = nil - 1;

    pub fn init(capacity: u32) LruCache {
        std.debug.assert(capacity >= 1 and capacity <= max_capacity);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *LruCache, gpa: Allocator) void {
        self.index.deinit(gpa);
        self.nodes.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const LruCache) usize {
        return self.index.count();
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const slot = self.index.get(key) orelse return null;
        self.moveToFront(slot);
        return self.nodes.items[slot].value;
    }

    /// Inserts or overwrites `key`, making it the most recently used entry.
    /// Evicts the least recently used entry if the capacity is exceeded.
    pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const entry = try self.index.getOrPut(gpa, key);
        if (entry.found_existing) {
            const slot = entry.value_ptr.*;
            self.nodes.items[slot].value = value;
            self.moveToFront(slot);
            return;
        }
        const slot = self.allocSlot(gpa) catch |err| {
            _ = self.index.swapRemove(key);
            return err;
        };
        entry.value_ptr.* = slot;
        self.nodes.items[slot] = .{ .key = key, .value = value, .prev = nil, .next = nil };
        self.pushFront(slot);
        if (self.index.count() > self.capacity) self.removeSlot(self.tail);
    }

    /// Removes `key`. Returns whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const kv = self.index.fetchSwapRemove(key) orelse return false;
        self.releaseSlot(kv.value);
        return true;
    }

    fn allocSlot(self: *LruCache, gpa: Allocator) Allocator.Error!Slot {
        if (self.free != nil) {
            const slot = self.free;
            self.free = self.nodes.items[slot].next;
            return slot;
        }
        const slot: Slot = @intCast(self.nodes.items.len);
        _ = try self.nodes.addOne(gpa);
        return slot;
    }

    fn removeSlot(self: *LruCache, slot: Slot) void {
        const removed = self.index.swapRemove(self.nodes.items[slot].key);
        std.debug.assert(removed);
        self.releaseSlot(slot);
    }

    fn releaseSlot(self: *LruCache, slot: Slot) void {
        self.unlink(slot);
        self.nodes.items[slot] = .{ .key = &.{}, .value = &.{}, .prev = nil, .next = self.free };
        self.free = slot;
    }

    fn pushFront(self: *LruCache, slot: Slot) void {
        const nodes = self.nodes.items;
        nodes[slot].prev = nil;
        nodes[slot].next = self.head;
        if (self.head != nil) nodes[self.head].prev = slot else self.tail = slot;
        self.head = slot;
    }

    fn unlink(self: *LruCache, slot: Slot) void {
        const nodes = self.nodes.items;
        const p = nodes[slot].prev;
        const n = nodes[slot].next;
        if (p != nil) nodes[p].next = n else self.head = n;
        if (n != nil) nodes[n].prev = p else self.tail = p;
    }

    fn moveToFront(self: *LruCache, slot: Slot) void {
        if (slot == self.head) return;
        self.unlink(slot);
        self.pushFront(slot);
    }
};

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and slot reuse" {
    var cache: LruCache = .init(3);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try cache.put(testing.allocator, "y", "2");
    try cache.put(testing.allocator, "z", "3");
    try testing.expectEqual(2, cache.nodes.items.len);
    try testing.expectEqualStrings("2", cache.get("y").?);
}

test "capacity one" {
    var cache: LruCache = .init(1);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqual(null, cache.get("a"));
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.count());
}
