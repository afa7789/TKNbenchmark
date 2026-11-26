//! A bounded least-recently-used cache from string keys to string values.
//!
//! Entries live in a pool of fixed-size nodes, threaded on an intrusive
//! doubly-linked list ordered from most (`head`) to least (`tail`) recently
//! used. A hash set of node indices, hashed and compared by the node's key,
//! finds the node of a key. Every operation runs in O(1) expected time, and
//! the pool never holds more than `capacity` nodes: an evicted or deleted
//! node is recycled through a free list.
//!
//! The set is an array hash map rather than `std.HashMapUnmanaged`: the latter
//! deletes with tombstones, which a long run of insertions and evictions piles
//! up until lookups degrade to linear scans. The array hash map removes
//! entries without leaving tombstones behind.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Cache = @This();

pub const max_capacity = 1_000_000;
/// The maximum length in bytes of a key or a value.
pub const max_token_len = 64;

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Node = struct {
    /// Towards `head` (more recently used); on the free list, unused.
    prev: Index,
    /// Towards `tail` (less recently used); on the free list, the next free node.
    next: Index,
    key_len: u8,
    value_len: u8,
    key_buf: [max_token_len]u8,
    value_buf: [max_token_len]u8,

    fn key(node: *const Node) []const u8 {
        return node.key_buf[0..node.key_len];
    }

    fn value(node: *const Node) []const u8 {
        return node.value_buf[0..node.value_len];
    }

    fn setKey(node: *Node, k: []const u8) void {
        @memcpy(node.key_buf[0..k.len], k);
        node.key_len = @intCast(k.len);
    }

    fn setValue(node: *Node, v: []const u8) void {
        @memcpy(node.value_buf[0..v.len], v);
        node.value_len = @intCast(v.len);
    }
};

fn hashKey(k: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, k));
}

/// Hashes and compares stored node indices by their keys.
const IndexContext = struct {
    nodes: []const Node,

    pub fn hash(ctx: IndexContext, index: Index) u32 {
        return hashKey(ctx.nodes[index].key());
    }

    pub fn eql(ctx: IndexContext, a: Index, b: Index, b_index: usize) bool {
        _ = ctx;
        _ = b_index;
        // Each key is held by exactly one node.
        return a == b;
    }
};

/// Looks up stored node indices by key.
const KeyAdapter = struct {
    nodes: []const Node,

    pub fn hash(_: KeyAdapter, k: []const u8) u32 {
        return hashKey(k);
    }

    pub fn eql(ctx: KeyAdapter, k: []const u8, index: Index, b_index: usize) bool {
        _ = b_index;
        return std.mem.eql(u8, k, ctx.nodes[index].key());
    }
};

/// Stores each key's hash, so probing compares hashes before touching a node.
const IndexSet = std.array_hash_map.Custom(Index, void, IndexContext, true);

capacity: u32,
nodes: std.ArrayList(Node) = .empty,
map: IndexSet = .empty,
head: Index = none,
tail: Index = none,
free: Index = none,

pub fn init(capacity: u32) Cache {
    assert(capacity >= 1 and capacity <= max_capacity);
    return .{ .capacity = capacity };
}

pub fn deinit(cache: *Cache, gpa: Allocator) void {
    cache.map.deinit(gpa);
    cache.nodes.deinit(gpa);
    cache.* = undefined;
}

/// The number of keys held.
pub fn size(cache: *const Cache) u32 {
    return @intCast(cache.map.count());
}

/// Returns the value of `key` and marks it most recently used, or returns
/// null if absent. The slice is valid until the next modification.
pub fn get(cache: *Cache, key: []const u8) ?[]const u8 {
    const index = cache.find(key) orelse return null;
    cache.promote(index);
    return cache.nodes.items[index].value();
}

/// Removes `key`; returns whether it was present.
pub fn del(cache: *Cache, key: []const u8) bool {
    const kv = cache.map.fetchSwapRemoveContextAdapted(key, cache.keyAdapter(), cache.indexContext()) orelse
        return false;
    cache.unlink(kv.key);
    cache.release(kv.key);
    return true;
}

/// Inserts or overwrites `key`, marks it most recently used, and evicts the
/// least recently used key if the cache would otherwise exceed its capacity.
pub fn set(cache: *Cache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    assert(key.len >= 1 and key.len <= max_token_len);
    assert(value.len <= max_token_len);

    if (cache.find(key)) |index| {
        cache.nodes.items[index].setValue(value);
        cache.promote(index);
        return;
    }

    // Make room before allocating, so the pool stays within capacity.
    if (cache.size() == cache.capacity) cache.evict();

    const index = try cache.acquire(gpa);
    errdefer cache.release(index);
    const node = &cache.nodes.items[index];
    node.setKey(key);
    node.setValue(value);

    const gop = try cache.map.getOrPutContextAdapted(gpa, key, cache.keyAdapter(), cache.indexContext());
    assert(!gop.found_existing);
    gop.key_ptr.* = index;
    cache.pushFront(index);
}

fn find(cache: *const Cache, key: []const u8) ?Index {
    return cache.map.getKeyAdapted(key, cache.keyAdapter());
}

fn evict(cache: *Cache) void {
    const index = cache.tail;
    assert(index != none);
    const removed = cache.map.swapRemoveContext(index, cache.indexContext());
    assert(removed);
    cache.unlink(index);
    cache.release(index);
}

fn keyAdapter(cache: *const Cache) KeyAdapter {
    return .{ .nodes = cache.nodes.items };
}

fn indexContext(cache: *const Cache) IndexContext {
    return .{ .nodes = cache.nodes.items };
}

/// Takes a node from the free list, or grows the pool.
fn acquire(cache: *Cache, gpa: Allocator) Allocator.Error!Index {
    if (cache.free != none) {
        const index = cache.free;
        cache.free = cache.nodes.items[index].next;
        return index;
    }
    const index: Index = @intCast(cache.nodes.items.len);
    _ = try cache.nodes.addOne(gpa);
    return index;
}

fn release(cache: *Cache, index: Index) void {
    cache.nodes.items[index].next = cache.free;
    cache.free = index;
}

fn promote(cache: *Cache, index: Index) void {
    if (cache.head == index) return;
    cache.unlink(index);
    cache.pushFront(index);
}

fn pushFront(cache: *Cache, index: Index) void {
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

fn unlink(cache: *Cache, index: Index) void {
    const nodes = cache.nodes.items;
    const node = &nodes[index];
    if (node.prev != none) nodes[node.prev].next = node.next else cache.head = node.next;
    if (node.next != none) nodes[node.next].prev = node.prev else cache.tail = node.prev;
}

test "eviction order follows recency" {
    const gpa = std.testing.allocator;
    var cache: Cache = .init(2);
    defer cache.deinit(gpa);

    try cache.set(gpa, "a", "1");
    try cache.set(gpa, "b", "2");
    try std.testing.expectEqualStrings("1", cache.get("a").?);
    try cache.set(gpa, "c", "3");
    try std.testing.expectEqual(null, cache.get("b"));
    try std.testing.expectEqualStrings("1", cache.get("a").?);
    try std.testing.expectEqualStrings("3", cache.get("c").?);
    try std.testing.expectEqual(2, cache.size());
}

test "pool never exceeds capacity" {
    const gpa = std.testing.allocator;
    var cache: Cache = .init(3);
    defer cache.deinit(gpa);

    var buf: [16]u8 = undefined;
    for (0..1000) |i| {
        const key = try std.fmt.bufPrint(&buf, "k{d}", .{i % 17});
        if (i % 5 == 0) {
            _ = cache.del(key);
        } else {
            try cache.set(gpa, key, key);
        }
        try std.testing.expect(cache.size() <= 3);
        try std.testing.expect(cache.nodes.items.len <= 3);
    }
}

test "max length keys and values" {
    const gpa = std.testing.allocator;
    var cache: Cache = .init(1);
    defer cache.deinit(gpa);

    const long = "x" ** max_token_len;
    try cache.set(gpa, long, long);
    try std.testing.expectEqualStrings(long, cache.get(long).?);
    try std.testing.expect(cache.del(long));
    try std.testing.expect(!cache.del(long));
    try std.testing.expectEqual(0, cache.size());
}
