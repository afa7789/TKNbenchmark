//! A fixed-capacity least-recently-used cache mapping byte-string keys to
//! byte-string values.
//!
//! Entries live in a node pool and are threaded onto an intrusive doubly
//! linked list ordered from most to least recently used; a hash map indexes
//! the pool by key. Lookups, insertions, overwrites and removals all run in
//! O(1) expected time. Both `get` and `put` mark the key as most recently used.
//!
//! The cache owns copies of every key and value. Released nodes keep their
//! buffers and are recycled through a free list, so steady-state churn does
//! not touch the allocator.
//!
//! Not thread-safe.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

const Index = u32;
const none: Index = std.math.maxInt(Index);

/// Upper bound on the number of map slots reserved up front; larger caches
/// grow on demand.
const max_initial_capacity = 1 << 16;

const Node = struct {
    key: std.ArrayList(u8) = .empty,
    value: std.ArrayList(u8) = .empty,
    /// Neighbour towards the most recently used end, or `none`.
    prev: Index = none,
    /// Neighbour towards the least recently used end, or `none`.
    /// For nodes on the free list, the next free node.
    next: Index = none,

    fn deinit(node: *Node, gpa: Allocator) void {
        node.key.deinit(gpa);
        node.value.deinit(gpa);
    }

    fn assign(list: *std.ArrayList(u8), gpa: Allocator, bytes: []const u8) Allocator.Error!void {
        list.clearRetainingCapacity();
        try list.appendSlice(gpa, bytes);
    }
};

gpa: Allocator,
capacity: Index,
/// Keys are slices of the owning node's `key` buffer. An array hash map is
/// used because its removals shift entries back rather than leaving
/// tombstones, which keeps probe lengths short under heavy insert/delete churn.
map: std.StringArrayHashMapUnmanaged(Index) = .empty,
nodes: std.ArrayList(Node) = .empty,
/// Most recently used node.
head: Index = none,
/// Least recently used node; the next eviction candidate.
tail: Index = none,
/// Singly linked (via `next`) list of released nodes available for reuse.
free: Index = none,

pub const InitError = Allocator.Error || error{InvalidCapacity};

pub fn init(gpa: Allocator, capacity: usize) InitError!LruCache {
    if (capacity < 1 or capacity >= none) return error.InvalidCapacity;
    var cache: LruCache = .{ .gpa = gpa, .capacity = @intCast(capacity) };
    try cache.map.ensureTotalCapacity(gpa, @min(capacity, max_initial_capacity));
    return cache;
}

pub fn deinit(cache: *LruCache) void {
    for (cache.nodes.items) |*node| node.deinit(cache.gpa);
    cache.nodes.deinit(cache.gpa);
    cache.map.deinit(cache.gpa);
    cache.* = undefined;
}

/// Number of keys currently held.
pub fn size(cache: *const LruCache) usize {
    return cache.map.count();
}

/// Returns the value for `key`, or null if absent; a hit refreshes recency.
/// The returned slice is valid until the next mutation of the cache.
pub fn get(cache: *LruCache, key: []const u8) ?[]const u8 {
    const index = cache.map.get(key) orelse return null;
    cache.moveToFront(index);
    return cache.nodes.items[index].value.items;
}

/// Inserts or overwrites `key`, making it most recently used and evicting the
/// least recently used entry if the cache would exceed its capacity.
pub fn put(cache: *LruCache, key: []const u8, value: []const u8) Allocator.Error!void {
    if (cache.map.get(key)) |index| {
        try Node.assign(&cache.nodes.items[index].value, cache.gpa, value);
        cache.moveToFront(index);
        return;
    }

    if (cache.map.count() >= cache.capacity) cache.evict();
    try cache.map.ensureUnusedCapacity(cache.gpa, 1);

    const index = try cache.acquireNode();
    errdefer cache.releaseNode(index);
    const node = &cache.nodes.items[index];
    try Node.assign(&node.key, cache.gpa, key);
    try Node.assign(&node.value, cache.gpa, value);

    cache.map.putAssumeCapacityNoClobber(node.key.items, index);
    cache.pushFront(index);
}

/// Removes `key`; returns whether it was present.
pub fn remove(cache: *LruCache, key: []const u8) bool {
    const entry = cache.map.fetchSwapRemove(key) orelse return false;
    cache.unlink(entry.value);
    cache.releaseNode(entry.value);
    return true;
}

fn evict(cache: *LruCache) void {
    const index = cache.tail;
    std.debug.assert(index != none);
    const removed = cache.map.swapRemove(cache.nodes.items[index].key.items);
    std.debug.assert(removed);
    cache.unlink(index);
    cache.releaseNode(index);
}

fn acquireNode(cache: *LruCache) Allocator.Error!Index {
    if (cache.free != none) {
        const index = cache.free;
        cache.free = cache.nodes.items[index].next;
        return index;
    }
    const index: Index = @intCast(cache.nodes.items.len);
    try cache.nodes.append(cache.gpa, .{});
    return index;
}

fn releaseNode(cache: *LruCache, index: Index) void {
    const node = &cache.nodes.items[index];
    node.prev = none;
    node.next = cache.free;
    cache.free = index;
}

fn pushFront(cache: *LruCache, index: Index) void {
    const node = &cache.nodes.items[index];
    node.prev = none;
    node.next = cache.head;
    if (cache.head != none) {
        cache.nodes.items[cache.head].prev = index;
    } else {
        cache.tail = index;
    }
    cache.head = index;
}

fn unlink(cache: *LruCache, index: Index) void {
    const node = &cache.nodes.items[index];
    if (node.prev != none) {
        cache.nodes.items[node.prev].next = node.next;
    } else {
        cache.head = node.next;
    }
    if (node.next != none) {
        cache.nodes.items[node.next].prev = node.prev;
    } else {
        cache.tail = node.prev;
    }
    node.prev = none;
    node.next = none;
}

fn moveToFront(cache: *LruCache, index: Index) void {
    if (cache.head == index) return;
    cache.unlink(index);
    cache.pushFront(index);
}

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put("c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.size());
}

test "overwrite refreshes recency" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try cache.put("a", "a much longer value than before");
    try cache.put("c", "3");
    try testing.expectEqualStrings("a much longer value than before", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and node reuse" {
    var cache: LruCache = try .init(testing.allocator, 3);
    defer cache.deinit();

    try cache.put("x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.size());
    try testing.expectEqual(null, cache.get("x"));

    try cache.put("y", "2");
    try testing.expectEqual(1, cache.nodes.items.len);
    try testing.expectEqualStrings("2", cache.get("y").?);
}

test "capacity one" {
    var cache: LruCache = try .init(testing.allocator, 1);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqual(null, cache.get("a"));
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.size());
}

test "rejects non-positive capacity" {
    try testing.expectError(error.InvalidCapacity, LruCache.init(testing.allocator, 0));
}
