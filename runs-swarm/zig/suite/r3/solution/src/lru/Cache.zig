//! A fixed-capacity LRU cache from short byte strings to short byte strings.
//!
//! Entries live in a pool of nodes addressed by `u32` index. The nodes form a
//! circular doubly linked list in recency order through a sentinel at index 0
//! (`sentinel.next` is the most recently used entry, `sentinel.prev` the least
//! recently used one). A hash map stores node indices and hashes/compares them
//! through the keys held by the nodes, so every key is stored exactly once.
//!
//! Every operation runs in O(1) expected time. The pool never holds more than
//! `capacity` live entries: when full, the evicted node is reused in place.
//! Removals leave tombstones in the open-addressing map, which would make
//! probes for absent keys degrade under steady insert/evict churn, so the map
//! is rehashed in place after a bounded number of removals (amortized O(1)).

const std = @import("std");
const Allocator = std.mem.Allocator;

const Cache = @This();

/// Maximum length in bytes of a key or a value.
pub const max_len = 64;

const Index = u32;
const sentinel: Index = 0;
/// Terminates the free list.
const nil: Index = std.math.maxInt(Index);

const Node = struct {
    /// Cached `hashKey(key())`, so rehashing never rereads key bytes.
    hash: u64,
    prev: Index,
    next: Index,
    key_len: u8,
    value_len: u8,
    key_buf: [max_len]u8,
    value_buf: [max_len]u8,

    fn key(node: *const Node) []const u8 {
        return node.key_buf[0..node.key_len];
    }

    fn value(node: *const Node) []const u8 {
        return node.value_buf[0..node.value_len];
    }

    fn setKey(node: *Node, bytes: []const u8) void {
        @memcpy(node.key_buf[0..bytes.len], bytes);
        node.key_len = @intCast(bytes.len);
        node.hash = hashKey(bytes);
    }

    fn setValue(node: *Node, bytes: []const u8) void {
        @memcpy(node.value_buf[0..bytes.len], bytes);
        node.value_len = @intCast(bytes.len);
    }
};

/// Hashes and compares stored node indices by the keys of their nodes.
const IndexContext = struct {
    nodes: []const Node,

    pub fn hash(ctx: IndexContext, index: Index) u64 {
        return ctx.nodes[index].hash;
    }

    pub fn eql(_: IndexContext, a: Index, b: Index) bool {
        // Each live key is held by exactly one node.
        return a == b;
    }
};

/// Looks up stored node indices by key bytes.
const KeyContext = struct {
    nodes: []const Node,

    pub fn hash(_: KeyContext, key: []const u8) u64 {
        return hashKey(key);
    }

    pub fn eql(ctx: KeyContext, key: []const u8, index: Index) bool {
        return std.mem.eql(u8, key, ctx.nodes[index].key());
    }
};

fn hashKey(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key);
}

/// A low load factor keeps linear probe sequences short even with tombstones.
const max_load_percentage = 50;
const Map = std.HashMapUnmanaged(Index, void, IndexContext, max_load_percentage);

/// The map is rehashed once removals since the last rehash exceed
/// `map.capacity() / tombstone_divisor`, bounding the share of tombstones.
const tombstone_divisor = 8;

pub const InitError = Allocator.Error || error{CapacityTooLarge};

gpa: Allocator,
capacity: Index,
/// Index 0 is the sentinel; all others are live entries or on the free list.
nodes: std.ArrayList(Node),
map: Map,
/// Head of the list of unused nodes, chained through `Node.next`.
free_head: Index,
/// Upper bound on the tombstones currently in `map`.
removals_since_rehash: usize,

pub fn init(gpa: Allocator, capacity: usize) InitError!Cache {
    std.debug.assert(capacity >= 1);
    // One index is taken by the sentinel and one is reserved as `nil`.
    if (capacity > std.math.maxInt(Index) - 2) return error.CapacityTooLarge;

    var nodes: std.ArrayList(Node) = .empty;
    try nodes.append(gpa, .{
        .hash = 0,
        .prev = sentinel,
        .next = sentinel,
        .key_len = 0,
        .value_len = 0,
        .key_buf = undefined,
        .value_buf = undefined,
    });
    return .{
        .gpa = gpa,
        .capacity = @intCast(capacity),
        .nodes = nodes,
        .map = .empty,
        .free_head = nil,
        .removals_since_rehash = 0,
    };
}

pub fn deinit(cache: *Cache) void {
    cache.map.deinit(cache.gpa);
    cache.nodes.deinit(cache.gpa);
    cache.* = undefined;
}

/// Number of entries currently held.
pub fn count(cache: *const Cache) usize {
    return cache.map.count();
}

/// Returns the value stored under `key` and marks it most recently used.
/// The returned slice is valid until the next mutating call.
pub fn get(cache: *Cache, key: []const u8) ?[]const u8 {
    const index = cache.find(key) orelse return null;
    cache.moveToFront(index);
    return cache.nodes.items[index].value();
}

/// Inserts or overwrites `key`, marking it most recently used. Evicts the
/// least recently used entry if the cache would exceed its capacity.
pub fn put(cache: *Cache, key: []const u8, value: []const u8) Allocator.Error!void {
    std.debug.assert(key.len <= max_len and value.len <= max_len);

    if (cache.find(key)) |index| {
        cache.nodes.items[index].setValue(value);
        cache.moveToFront(index);
        return;
    }

    // Reserve map space first so that a failed allocation leaves the cache intact.
    try cache.map.ensureUnusedCapacityContext(cache.gpa, 1, cache.indexContext());

    const index = if (cache.map.count() >= cache.capacity) blk: {
        const lru = cache.nodes.items[sentinel].prev;
        cache.unlink(lru);
        const removed = cache.map.removeContext(lru, cache.indexContext());
        std.debug.assert(removed);
        cache.noteRemoval();
        break :blk lru;
    } else try cache.allocNode();

    const node = &cache.nodes.items[index];
    node.setKey(key);
    node.setValue(value);
    cache.linkFront(index);
    cache.map.putAssumeCapacityNoClobberContext(index, {}, cache.indexContext());
}

/// Removes `key`. Returns whether it was present.
pub fn remove(cache: *Cache, key: []const u8) bool {
    const kv = cache.map.fetchRemoveAdapted(key, cache.keyContext()) orelse return false;
    const index = kv.key;
    cache.noteRemoval();
    cache.unlink(index);
    cache.nodes.items[index].next = cache.free_head;
    cache.free_head = index;
    return true;
}

fn find(cache: *const Cache, key: []const u8) ?Index {
    if (key.len > max_len) return null;
    return cache.map.getKeyAdapted(key, cache.keyContext());
}

fn noteRemoval(cache: *Cache) void {
    cache.removals_since_rehash += 1;
    if (cache.removals_since_rehash > cache.map.capacity() / tombstone_divisor) {
        cache.map.rehash(cache.indexContext());
        cache.removals_since_rehash = 0;
    }
}

fn allocNode(cache: *Cache) Allocator.Error!Index {
    if (cache.free_head != nil) {
        const index = cache.free_head;
        cache.free_head = cache.nodes.items[index].next;
        return index;
    }
    const index: Index = @intCast(cache.nodes.items.len);
    _ = try cache.nodes.addOne(cache.gpa);
    return index;
}

fn unlink(cache: *Cache, index: Index) void {
    const nodes = cache.nodes.items;
    const node = &nodes[index];
    nodes[node.prev].next = node.next;
    nodes[node.next].prev = node.prev;
}

fn linkFront(cache: *Cache, index: Index) void {
    const nodes = cache.nodes.items;
    const first = nodes[sentinel].next;
    nodes[index].prev = sentinel;
    nodes[index].next = first;
    nodes[first].prev = index;
    nodes[sentinel].next = index;
}

fn moveToFront(cache: *Cache, index: Index) void {
    if (cache.nodes.items[sentinel].next == index) return;
    cache.unlink(index);
    cache.linkFront(index);
}

fn indexContext(cache: *const Cache) IndexContext {
    return .{ .nodes = cache.nodes.items };
}

fn keyContext(cache: *const Cache) KeyContext {
    return .{ .nodes = cache.nodes.items };
}

const testing = std.testing;

test "evicts the least recently used entry" {
    var cache: Cache = try .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put("c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("1", cache.get("a").?);
    try testing.expectEqualStrings("3", cache.get("c").?);
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency and value" {
    var cache: Cache = try .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try cache.put("a", "9");
    try cache.put("c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove frees a slot that is reused" {
    var cache: Cache = try .init(testing.allocator, 2);
    defer cache.deinit();

    try cache.put("x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("x"));

    try cache.put("y", "2");
    try cache.put("z", "3");
    try testing.expectEqual(2, cache.count());
    try testing.expectEqual(3, cache.nodes.items.len); // sentinel + 2
    try testing.expectEqualStrings("2", cache.get("y").?);
    try testing.expectEqualStrings("3", cache.get("z").?);
}

test "capacity one" {
    var cache: Cache = try .init(testing.allocator, 1);
    defer cache.deinit();

    try cache.put("a", "1");
    try cache.put("b", "2");
    try testing.expectEqual(null, cache.get("a"));
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.count());
}

test "keys and values of maximum length" {
    var cache: Cache = try .init(testing.allocator, 4);
    defer cache.deinit();

    const long_key = "k" ** max_len;
    const long_value = "v" ** max_len;
    try cache.put(long_key, long_value);
    try testing.expectEqualStrings(long_value, cache.get(long_key).?);
    try testing.expectEqual(null, cache.get(long_key ++ "k"));
    try testing.expect(!cache.remove(long_key ++ "k"));
}

test "matches a reference model under random operations" {
    const gpa = testing.allocator;
    var prng: std.Random.DefaultPrng = .init(0x5eed);
    const random = prng.random();

    const capacity = 16;
    var cache: Cache = try .init(gpa, capacity);
    defer cache.deinit();

    // Reference: keys in recency order, most recent last.
    var model: std.ArrayList(struct { key: u8, value: u32 }) = .empty;
    defer model.deinit(gpa);

    for (0..20_000) |_| {
        const k: u8 = random.uintLessThan(u8, 40);
        const key: []const u8 = &.{ 'a' + k / 26, 'a' + k % 26 };
        const found: ?usize = for (model.items, 0..) |e, i| {
            if (e.key == k) break i;
        } else null;

        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const v = random.int(u32);
                var buf: [16]u8 = undefined;
                try cache.put(key, try std.fmt.bufPrint(&buf, "{d}", .{v}));
                if (found) |i| _ = model.orderedRemove(i);
                if (model.items.len == capacity) _ = model.orderedRemove(0);
                try model.append(gpa, .{ .key = k, .value = v });
            },
            1 => {
                const got = cache.get(key);
                if (found) |i| {
                    const e = model.orderedRemove(i);
                    try model.append(gpa, e);
                    var buf: [16]u8 = undefined;
                    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{d}", .{e.value}), got.?);
                } else {
                    try testing.expectEqual(null, got);
                }
            },
            else => {
                try testing.expectEqual(found != null, cache.remove(key));
                if (found) |i| _ = model.orderedRemove(i);
            },
        }
        try testing.expectEqual(model.items.len, cache.count());
    }
}
