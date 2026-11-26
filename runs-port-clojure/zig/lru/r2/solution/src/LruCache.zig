//! A string-keyed LRU cache with O(1) expected-time operations.
//!
//! Entries live in a flat array of nodes threaded onto a circular doubly
//! linked list (index 0 is the sentinel), ordered from most to least recently
//! used. The hash map stores only node indices; hashing and equality are
//! resolved through the node array, so each key is stored exactly once.
//!
//! An array hash map is used because its deletions leave no tombstones, so
//! heavy insert/evict churn cannot degrade lookups.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

const Index = u32;
const sentinel: Index = 0;
const no_node: Index = std.math.maxInt(Index);

const Node = struct {
    prev: Index,
    next: Index,
    /// Owned storage holding the key immediately followed by the value.
    /// Its length is the allocated capacity; only a prefix may be in use.
    buf: []u8,
    key_len: u32,
    value_len: u32,

    fn key(node: *const Node) []const u8 {
        return node.buf[0..node.key_len];
    }

    fn value(node: *const Node) []const u8 {
        return node.buf[node.key_len..][0..node.value_len];
    }
};

/// Hashes stored entries (map keys are node indices).
const IndexContext = struct {
    nodes: []const Node,

    pub fn hash(ctx: IndexContext, index: Index) u32 {
        return hashKey(ctx.nodes[index].key());
    }

    pub fn eql(_: IndexContext, a: Index, b: Index, _: usize) bool {
        return a == b;
    }
};

/// Lets the map be queried with a key string instead of a node index.
const KeyAdapter = struct {
    nodes: []const Node,

    pub fn hash(_: KeyAdapter, key: []const u8) u32 {
        return hashKey(key);
    }

    pub fn eql(ctx: KeyAdapter, key: []const u8, index: Index, _: usize) bool {
        return std.mem.eql(u8, key, ctx.nodes[index].key());
    }
};

fn hashKey(key: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, key));
}

/// Stored hashes keep `eql` to one call per hit and make resizing cheap.
const Map = std.array_hash_map.Custom(Index, void, IndexContext, true);

allocator: Allocator,
capacity: usize,
/// Node storage; `nodes.items[0]` is the list sentinel.
nodes: std.ArrayList(Node),
map: Map,
/// Head of a singly linked list (through `next`) of deleted, reusable nodes.
free_head: Index,

pub fn init(allocator: Allocator, capacity: usize) Allocator.Error!LruCache {
    var cache: LruCache = .{
        .allocator = allocator,
        .capacity = capacity,
        .nodes = .empty,
        .map = .empty,
        .free_head = no_node,
    };
    errdefer cache.deinit();
    try cache.nodes.append(allocator, .{
        .prev = sentinel,
        .next = sentinel,
        .buf = &.{},
        .key_len = 0,
        .value_len = 0,
    });
    // The cache never holds more than `capacity` entries, so sizing the map
    // up front avoids rehashing while it fills.
    const reserve = @min(capacity, std.math.maxInt(Index) - 1);
    try cache.map.ensureTotalCapacityContext(allocator, reserve, cache.indexContext());
    return cache;
}

pub fn deinit(cache: *LruCache) void {
    for (cache.nodes.items) |node| cache.allocator.free(node.buf);
    cache.nodes.deinit(cache.allocator);
    cache.map.deinit(cache.allocator);
    cache.* = undefined;
}

pub fn count(cache: *const LruCache) usize {
    return cache.map.count();
}

/// Returns the value for `key` and marks it most recently used. The returned
/// slice is valid until the next mutating call.
pub fn get(cache: *LruCache, key: []const u8) ?[]const u8 {
    const index = cache.lookup(key) orelse return null;
    cache.moveToFront(index);
    return cache.nodes.items[index].value();
}

/// Inserts or overwrites `key`, making it most recently used, and evicts the
/// least recently used entry if the cache would exceed its capacity.
pub fn put(cache: *LruCache, key: []const u8, value: []const u8) Allocator.Error!void {
    if (cache.lookup(key)) |index| {
        try cache.store(index, key, value);
        cache.moveToFront(index);
        return;
    }
    // With zero capacity any insertion is evicted immediately.
    if (cache.capacity == 0) return;

    const index = try cache.acquireNode();
    errdefer cache.release(index);
    try cache.store(index, key, value);
    const gop = try cache.map.getOrPutContextAdapted(
        cache.allocator,
        key,
        cache.keyAdapter(),
        cache.indexContext(),
    );
    std.debug.assert(!gop.found_existing);
    gop.key_ptr.* = index;
    cache.linkFront(index);
}

/// Removes `key`, returning whether it was present.
pub fn remove(cache: *LruCache, key: []const u8) bool {
    const index = cache.lookup(key) orelse return false;
    cache.forget(key);
    cache.unlink(index);
    cache.release(index);
    return true;
}

fn lookup(cache: *const LruCache, key: []const u8) ?Index {
    const slot = cache.map.getIndexAdapted(key, cache.keyAdapter()) orelse return null;
    return cache.map.keys()[slot];
}

/// Drops `key`, which must be present, from the map.
fn forget(cache: *LruCache, key: []const u8) void {
    const removed = cache.map.swapRemoveContextAdapted(key, cache.keyAdapter(), cache.indexContext());
    std.debug.assert(removed);
}

fn indexContext(cache: *const LruCache) IndexContext {
    return .{ .nodes = cache.nodes.items };
}

fn keyAdapter(cache: *const LruCache) KeyAdapter {
    return .{ .nodes = cache.nodes.items };
}

/// Returns an unlinked node not present in the map, ready to be filled. When
/// the cache is full, the least recently used entry is evicted and reused.
fn acquireNode(cache: *LruCache) Allocator.Error!Index {
    if (cache.count() >= cache.capacity) {
        const lru = cache.nodes.items[sentinel].prev;
        std.debug.assert(lru != sentinel);
        const evicted = cache.nodes.items[lru].key();
        cache.forget(evicted);
        cache.unlink(lru);
        return lru;
    }
    if (cache.free_head != no_node) {
        const index = cache.free_head;
        cache.free_head = cache.nodes.items[index].next;
        return index;
    }
    if (cache.nodes.items.len > std.math.maxInt(Index) - 1) return error.OutOfMemory;
    const index: Index = @intCast(cache.nodes.items.len);
    try cache.nodes.append(cache.allocator, .{
        .prev = no_node,
        .next = no_node,
        .buf = &.{},
        .key_len = 0,
        .value_len = 0,
    });
    return index;
}

/// Returns an unlinked node to the free list.
fn release(cache: *LruCache, index: Index) void {
    const node = &cache.nodes.items[index];
    node.key_len = 0;
    node.value_len = 0;
    node.next = cache.free_head;
    node.prev = no_node;
    cache.free_head = index;
}

/// Writes `key` and `value` into the node, growing its buffer if needed.
/// `key` must not alias the node's own buffer.
fn store(cache: *LruCache, index: Index, key: []const u8, value: []const u8) Allocator.Error!void {
    const key_len = std.math.cast(u32, key.len) orelse return error.OutOfMemory;
    const value_len = std.math.cast(u32, value.len) orelse return error.OutOfMemory;
    const node = &cache.nodes.items[index];
    const needed = key.len + value.len;
    if (node.buf.len < needed) {
        const buf = try cache.allocator.alloc(u8, needed);
        cache.allocator.free(node.buf);
        node.buf = buf;
    }
    @memcpy(node.buf[0..key.len], key);
    @memcpy(node.buf[key.len..][0..value.len], value);
    node.key_len = key_len;
    node.value_len = value_len;
}

fn unlink(cache: *LruCache, index: Index) void {
    const nodes = cache.nodes.items;
    const node = &nodes[index];
    nodes[node.prev].next = node.next;
    nodes[node.next].prev = node.prev;
    node.prev = no_node;
    node.next = no_node;
}

fn linkFront(cache: *LruCache, index: Index) void {
    const nodes = cache.nodes.items;
    const first = nodes[sentinel].next;
    nodes[index].prev = sentinel;
    nodes[index].next = first;
    nodes[first].prev = index;
    nodes[sentinel].next = index;
}

fn moveToFront(cache: *LruCache, index: Index) void {
    if (cache.nodes.items[sentinel].next == index) return;
    cache.unlink(index);
    cache.linkFront(index);
}

const testing = std.testing;

test "evicts the least recently used entry" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit();
    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put("c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency and value" {
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

test "remove frees slots for reuse" {
    var cache: LruCache = try .init(testing.allocator, 3);
    defer cache.deinit();
    try cache.put("x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("x"));
    for (0..10) |i| {
        var key_buf: [8]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "k{d}", .{i});
        try cache.put(key, key);
        if (i % 2 == 0) try testing.expect(cache.remove(key));
    }
    try testing.expectEqual(3, cache.count());
    try testing.expectEqual(4, cache.nodes.items.len);
    try testing.expectEqualStrings("k9", cache.get("k9").?);
}

test "zero capacity stores nothing" {
    var cache: LruCache = try .init(testing.allocator, 0);
    defer cache.deinit();
    try cache.put("a", "1");
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("a"));
}
