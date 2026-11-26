//! A fixed-capacity least-recently-used cache mapping byte-string keys to
//! byte-string values. Every operation runs in O(1) expected time.
//!
//! Keys and values are borrowed, not copied: the caller must keep the memory
//! behind every slice passed to `set` alive for as long as the cache may
//! return it (in practice, for the lifetime of the cache).
//!
//! Recency order is kept in an intrusive doubly linked list threaded through
//! a node pool by index; the index map uses backward-shift deletion, so
//! heavy insert/evict churn never degrades lookups with tombstones.

const LruCache = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const Index = u32;
const none: Index = std.math.maxInt(Index);

/// Largest supported capacity; node indices must stay below `none`.
pub const max_capacity: usize = none - 1;

const Node = struct {
    key: []const u8,
    value: []const u8,
    /// Towards the most recently used end; `none` at the head.
    prev: Index,
    /// Towards the least recently used end; `none` at the tail. Also links
    /// the free list for released nodes.
    next: Index,
};

capacity: usize,
nodes: std.ArrayList(Node) = .empty,
index: std.StringArrayHashMapUnmanaged(Index) = .empty,
/// Most recently used node.
head: Index = none,
/// Least recently used node.
tail: Index = none,
/// Singly linked list (via `Node.next`) of released nodes available for reuse.
free: Index = none,

pub fn init(capacity: usize) LruCache {
    assert(capacity <= max_capacity);
    return .{ .capacity = capacity };
}

pub fn deinit(self: *LruCache, gpa: Allocator) void {
    self.nodes.deinit(gpa);
    self.index.deinit(gpa);
    self.* = undefined;
}

/// Number of keys currently held.
pub fn count(self: *const LruCache) usize {
    return self.index.count();
}

/// Inserts or overwrites `key`, making it the most recently used entry.
/// Evicts the least recently used entry if the cache would exceed capacity.
/// On error the cache is left unchanged.
pub fn set(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    if (self.index.get(key)) |i| {
        self.nodes.items[i].value = value;
        self.touch(i);
        return;
    }
    if (self.capacity == 0) return;

    // Reserve everything up front so the mutations below cannot fail midway.
    try self.index.ensureUnusedCapacity(gpa, 1);
    if (self.free == none and self.count() < self.capacity) {
        try self.nodes.ensureUnusedCapacity(gpa, 1);
    }

    const i = if (self.count() == self.capacity) self.evictLru() else self.allocNode();
    self.nodes.items[i] = .{ .key = key, .value = value, .prev = none, .next = none };
    self.pushFront(i);
    self.index.putAssumeCapacityNoClobber(key, i);
}

/// Returns the value stored under `key` and marks it most recently used,
/// or null if absent.
pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
    const i = self.index.get(key) orelse return null;
    self.touch(i);
    return self.nodes.items[i].value;
}

/// Removes `key`. Returns whether it was present.
pub fn remove(self: *LruCache, key: []const u8) bool {
    const kv = self.index.fetchSwapRemove(key) orelse return false;
    self.unlink(kv.value);
    self.releaseNode(kv.value);
    return true;
}

/// Moves node `i` to the most recently used position.
fn touch(self: *LruCache, i: Index) void {
    if (self.head == i) return;
    self.unlink(i);
    self.pushFront(i);
}

/// Detaches the least recently used entry and returns its node for reuse.
fn evictLru(self: *LruCache) Index {
    const i = self.tail;
    assert(i != none);
    assert(self.index.swapRemove(self.nodes.items[i].key));
    self.unlink(i);
    return i;
}

/// Returns a node from the free list, or appends one using reserved capacity.
fn allocNode(self: *LruCache) Index {
    if (self.free != none) {
        const i = self.free;
        self.free = self.nodes.items[i].next;
        return i;
    }
    const i: Index = @intCast(self.nodes.items.len);
    _ = self.nodes.addOneAssumeCapacity();
    return i;
}

fn releaseNode(self: *LruCache, i: Index) void {
    self.nodes.items[i] = .{ .key = &.{}, .value = &.{}, .prev = none, .next = self.free };
    self.free = i;
}

fn pushFront(self: *LruCache, i: Index) void {
    const nodes = self.nodes.items;
    nodes[i].prev = none;
    nodes[i].next = self.head;
    if (self.head != none) nodes[self.head].prev = i else self.tail = i;
    self.head = i;
}

fn unlink(self: *LruCache, i: Index) void {
    const nodes = self.nodes.items;
    const node = nodes[i];
    if (node.prev != none) nodes[node.prev].next = node.next else self.head = node.next;
    if (node.next != none) nodes[node.next].prev = node.prev else self.tail = node.prev;
}

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try cache.set(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.set(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("1", cache.get("a").?);
    try testing.expectEqualStrings("3", cache.get("c").?);
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try cache.set(testing.allocator, "b", "2");
    try cache.set(testing.allocator, "a", "9");
    try cache.set(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
}

test "remove and node reuse" {
    var cache: LruCache = .init(3);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("x"));

    try cache.set(testing.allocator, "y", "2");
    try cache.set(testing.allocator, "z", "3");
    try testing.expectEqual(2, cache.nodes.items.len);
    try testing.expect(cache.remove("y"));
    try cache.set(testing.allocator, "w", "4");
    try cache.set(testing.allocator, "v", "5");
    try cache.set(testing.allocator, "u", "6");
    try testing.expectEqual(3, cache.count());
    try testing.expectEqual(null, cache.get("z"));
    try testing.expectEqual(3, cache.nodes.items.len);
}

test "zero capacity holds nothing" {
    var cache: LruCache = .init(0);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("a"));
}
