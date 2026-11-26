//! A fixed-capacity LRU cache mapping short byte-string keys to short
//! byte-string values, with O(1) expected time per operation.
//!
//! Entries live in a growable array of nodes, linked into a doubly linked
//! recency list by index (head = most recently used). A hash set of node
//! indices, hashed and compared through the keys stored in the nodes, maps a
//! key to its node without storing the key twice. Slots freed by `del` are
//! kept on a free list and reused; once the cache is full, the least recently
//! used node is recycled in place for the new entry.

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Cache = @This();

/// Maximum length in bytes of a key or a value.
pub const max_len = 64;

/// Maximum supported capacity; node indices must fit in `Index` with `nil`
/// left over as a sentinel.
pub const max_capacity = std.math.maxInt(Index) - 1;

const Index = u32;
const nil: Index = std.math.maxInt(Index);

const Node = struct {
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

    fn setKey(node: *Node, k: []const u8) void {
        assert(k.len <= max_len);
        @memcpy(node.key_buf[0..k.len], k);
        node.key_len = @intCast(k.len);
    }

    fn setValue(node: *Node, v: []const u8) void {
        assert(v.len <= max_len);
        @memcpy(node.value_buf[0..v.len], v);
        node.value_len = @intCast(v.len);
    }
};

fn hashKey(key: []const u8) u32 {
    return @truncate(std.hash.Wyhash.hash(0, key));
}

/// Context for the index set: an index stands for the key of its node.
const IndexContext = struct {
    nodes: []const Node,

    pub fn hash(ctx: IndexContext, index: Index) u32 {
        return hashKey(ctx.nodes[index].key());
    }

    pub fn eql(_: IndexContext, a: Index, b: Index, _: usize) bool {
        // Keys in the set are unique, so equal keys mean equal indices.
        return a == b;
    }
};

/// Adapter for looking up the index set by key bytes.
const KeyAdapter = struct {
    nodes: []const Node,

    pub fn hash(_: KeyAdapter, key: []const u8) u32 {
        return hashKey(key);
    }

    pub fn eql(adapter: KeyAdapter, key: []const u8, index: Index, _: usize) bool {
        return std.mem.eql(u8, key, adapter.nodes[index].key());
    }
};

/// An array hash map rather than `std.HashMapUnmanaged`: its removals leave
/// no tombstones behind, so lookups stay fast under the constant
/// insert/evict churn of a full cache.
const IndexSet = std.ArrayHashMapUnmanaged(Index, void, IndexContext, true);

capacity: Index,
nodes: std.ArrayList(Node) = .empty,
index: IndexSet = .empty,
/// Most recently used entry.
head: Index = nil,
/// Least recently used entry.
tail: Index = nil,
/// Unused slots of `nodes`, chained through `Node.next`.
free_list: Index = nil,

/// Creates an empty cache holding at most `capacity` keys.
pub fn init(capacity: usize) Cache {
    assert(capacity >= 1 and capacity <= max_capacity);
    return .{ .capacity = @intCast(capacity) };
}

pub fn deinit(cache: *Cache, gpa: Allocator) void {
    cache.index.deinit(gpa);
    cache.nodes.deinit(gpa);
    cache.* = undefined;
}

/// Number of keys currently held.
pub fn count(cache: *const Cache) usize {
    return cache.index.count();
}

/// Returns the value stored for `key` and marks it most recently used.
/// The returned slice is valid until the next mutating call.
pub fn get(cache: *Cache, key: []const u8) ?[]const u8 {
    const i = cache.find(key) orelse return null;
    cache.moveToFront(i);
    return cache.nodes.items[i].value();
}

/// Inserts or overwrites `key`, marking it most recently used. Evicts the
/// least recently used key if the cache would exceed its capacity.
pub fn set(cache: *Cache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    assert(key.len <= max_len and value.len <= max_len);

    if (cache.find(key)) |i| {
        cache.nodes.items[i].setValue(value);
        cache.moveToFront(i);
        return;
    }

    // Reserve everything up front so that a failed allocation leaves the
    // cache unchanged.
    try cache.index.ensureUnusedCapacityContext(gpa, 1, cache.indexContext());
    const i = if (cache.count() == cache.capacity) cache.evict() else try cache.allocNode(gpa);

    const node = &cache.nodes.items[i];
    node.setKey(key);
    node.setValue(value);
    cache.linkFront(i);
    cache.index.putAssumeCapacityNoClobberContext(i, {}, cache.indexContext());
}

/// Removes `key`. Returns whether it was present.
pub fn del(cache: *Cache, key: []const u8) bool {
    const i = cache.find(key) orelse return false;
    cache.forget(i);
    cache.nodes.items[i].next = cache.free_list;
    cache.free_list = i;
    return true;
}

fn indexContext(cache: *const Cache) IndexContext {
    return .{ .nodes = cache.nodes.items };
}

fn find(cache: *const Cache, key: []const u8) ?Index {
    const ptr = cache.index.getKeyPtrAdapted(key, KeyAdapter{ .nodes = cache.nodes.items }) orelse return null;
    return ptr.*;
}

/// Returns an unused node slot, reusing a freed one if possible.
fn allocNode(cache: *Cache, gpa: Allocator) Allocator.Error!Index {
    if (cache.free_list != nil) {
        const i = cache.free_list;
        cache.free_list = cache.nodes.items[i].next;
        return i;
    }
    const i: Index = @intCast(cache.nodes.items.len);
    _ = try cache.nodes.addOne(gpa);
    return i;
}

/// Drops the least recently used entry and returns its now unused slot.
fn evict(cache: *Cache) Index {
    const i = cache.tail;
    assert(i != nil);
    cache.forget(i);
    return i;
}

/// Removes node `i` from both the index and the recency list.
fn forget(cache: *Cache, i: Index) void {
    // Must run while the node still holds its key: the index hashes it.
    const removed = cache.index.swapRemoveContext(i, cache.indexContext());
    assert(removed);
    cache.unlink(i);
}

fn unlink(cache: *Cache, i: Index) void {
    const nodes = cache.nodes.items;
    const node = &nodes[i];
    if (node.prev != nil) nodes[node.prev].next = node.next else cache.head = node.next;
    if (node.next != nil) nodes[node.next].prev = node.prev else cache.tail = node.prev;
}

fn linkFront(cache: *Cache, i: Index) void {
    const nodes = cache.nodes.items;
    nodes[i].prev = nil;
    nodes[i].next = cache.head;
    if (cache.head != nil) nodes[cache.head].prev = i else cache.tail = i;
    cache.head = i;
}

fn moveToFront(cache: *Cache, i: Index) void {
    if (cache.head == i) return;
    cache.unlink(i);
    cache.linkFront(i);
}

const testing = std.testing;

fn expectGet(cache: *Cache, key: []const u8, expected: ?[]const u8) !void {
    const actual = cache.get(key);
    if (expected) |e| {
        try testing.expect(actual != null);
        try testing.expectEqualStrings(e, actual.?);
    } else {
        try testing.expect(actual == null);
    }
}

test "evicts least recently used" {
    const gpa = testing.allocator;
    var cache: Cache = .init(2);
    defer cache.deinit(gpa);

    try cache.set(gpa, "a", "1");
    try cache.set(gpa, "b", "2");
    try expectGet(&cache, "a", "1");
    try cache.set(gpa, "c", "3");
    try expectGet(&cache, "b", null);
    try expectGet(&cache, "a", "1");
    try expectGet(&cache, "c", "3");
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    const gpa = testing.allocator;
    var cache: Cache = .init(2);
    defer cache.deinit(gpa);

    try cache.set(gpa, "a", "1");
    try cache.set(gpa, "b", "2");
    try cache.set(gpa, "a", "a much longer value");
    try cache.set(gpa, "c", "3");
    try expectGet(&cache, "a", "a much longer value");
    try expectGet(&cache, "b", null);
    try expectGet(&cache, "c", "3");
}

test "del frees slots for reuse" {
    const gpa = testing.allocator;
    var cache: Cache = .init(3);
    defer cache.deinit(gpa);

    try cache.set(gpa, "x", "1");
    try testing.expect(cache.del("x"));
    try testing.expect(!cache.del("x"));
    try testing.expectEqual(0, cache.count());
    try expectGet(&cache, "x", null);

    for (0..3) |n| {
        var buf: [8]u8 = undefined;
        const k = try std.fmt.bufPrint(&buf, "k{d}", .{n});
        try cache.set(gpa, k, k);
    }
    try testing.expectEqual(3, cache.nodes.items.len);
    try testing.expect(cache.del("k1"));
    try cache.set(gpa, "k3", "v");
    try testing.expectEqual(3, cache.nodes.items.len);
    try testing.expectEqual(3, cache.count());
    try expectGet(&cache, "k0", "k0");
}

test "capacity one" {
    const gpa = testing.allocator;
    var cache: Cache = .init(1);
    defer cache.deinit(gpa);

    try cache.set(gpa, "a", "1");
    try cache.set(gpa, "b", "2");
    try expectGet(&cache, "a", null);
    try expectGet(&cache, "b", "2");
    try testing.expectEqual(1, cache.count());
    try testing.expect(cache.del("b"));
    try testing.expect(cache.head == nil and cache.tail == nil);
}

test "matches a naive model" {
    const gpa = testing.allocator;
    const capacity = 7;
    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);

    // Model: keys ordered from least to most recently used.
    var model_keys: [capacity + 1]u8 = undefined;
    var model_values: [capacity + 1]u8 = undefined;
    var model_len: usize = 0;

    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();
    for (0..20_000) |_| {
        const k = random.uintLessThan(u8, 20);
        const key: []const u8 = &.{'a' + k};
        const pos = std.mem.indexOfScalar(u8, model_keys[0..model_len], k);
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const v = random.int(u8);
                try cache.set(gpa, key, &.{v});
                if (pos) |p| {
                    std.mem.copyForwards(u8, model_keys[p .. model_len - 1], model_keys[p + 1 .. model_len]);
                    std.mem.copyForwards(u8, model_values[p .. model_len - 1], model_values[p + 1 .. model_len]);
                    model_len -= 1;
                }
                model_keys[model_len] = k;
                model_values[model_len] = v;
                model_len += 1;
                if (model_len > capacity) {
                    std.mem.copyForwards(u8, model_keys[0 .. model_len - 1], model_keys[1..model_len]);
                    std.mem.copyForwards(u8, model_values[0 .. model_len - 1], model_values[1..model_len]);
                    model_len -= 1;
                }
            },
            1 => {
                const got = cache.get(key);
                if (pos) |p| {
                    const v = model_values[p];
                    try testing.expectEqualSlices(u8, &.{v}, got.?);
                    std.mem.copyForwards(u8, model_keys[p .. model_len - 1], model_keys[p + 1 .. model_len]);
                    std.mem.copyForwards(u8, model_values[p .. model_len - 1], model_values[p + 1 .. model_len]);
                    model_keys[model_len - 1] = k;
                    model_values[model_len - 1] = v;
                } else {
                    try testing.expect(got == null);
                }
            },
            else => {
                try testing.expectEqual(pos != null, cache.del(key));
                if (pos) |p| {
                    std.mem.copyForwards(u8, model_keys[p .. model_len - 1], model_keys[p + 1 .. model_len]);
                    std.mem.copyForwards(u8, model_values[p .. model_len - 1], model_values[p + 1 .. model_len]);
                    model_len -= 1;
                }
            },
        }
        try testing.expectEqual(model_len, cache.count());
    }
}
