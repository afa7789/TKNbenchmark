//! Fixed-capacity LRU cache keyed by byte strings: a chained hash table plus
//! an intrusive doubly linked recency list.
//!
//! Entries live in a preallocated pool and refer to each other by 32-bit
//! index, which keeps nodes small and cache-friendly. Index 0 is a sentinel
//! that serves both as the list head and as the "none" marker for chains.
//!
//! The cache does not copy keys or values: callers pass slices whose storage
//! must outlive the entries referring to them. Every operation runs in O(1)
//! expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Lru = @This();

const Index = u32;
const nil: Index = 0;

const Node = struct {
    key: []const u8,
    value: []const u8,
    hash: u64,
    /// Towards the most recently used entry.
    prev: Index,
    /// Towards the least recently used entry.
    next: Index,
    /// Next entry in the same bucket, or the free-list link.
    chain: Index,
};

/// `nodes[0]` is the list sentinel.
nodes: []Node,
/// Head index per bucket, `nil` if empty. Length is a power of two.
buckets: []Index,
/// Maximum number of live keys.
capacity: usize,
/// Current number of live keys.
len: usize = 0,
/// Nodes handed out so far (excluding the sentinel).
pool_len: Index = 0,
/// Recycled nodes, linked through `chain`.
free_head: Index = nil,

pub const InitError = Allocator.Error || error{ZeroCapacity};

/// Create a cache holding at most `capacity` keys. `max_entries` is an upper
/// bound on the number of keys that will ever be live at once (it may be
/// smaller than `capacity` when the caller knows the workload is short);
/// storage is preallocated for `min(capacity, max_entries)` entries.
pub fn init(gpa: Allocator, capacity: usize, max_entries: usize) InitError!Lru {
    if (capacity == 0) return error.ZeroCapacity;

    const live = @max(1, @min(capacity, max_entries));
    if (live >= std.math.maxInt(Index) - 1) return error.OutOfMemory;

    // Load factor <= 0.5.
    const bucket_count = std.math.ceilPowerOfTwo(usize, @max(16, live * 2)) catch
        return error.OutOfMemory;

    const nodes = try gpa.alloc(Node, live + 1);
    errdefer gpa.free(nodes);
    const buckets = try gpa.alloc(Index, bucket_count);
    @memset(buckets, nil);

    nodes[nil].prev = nil;
    nodes[nil].next = nil;
    return .{ .nodes = nodes, .buckets = buckets, .capacity = capacity };
}

pub fn deinit(self: *Lru, gpa: Allocator) void {
    gpa.free(self.nodes);
    gpa.free(self.buckets);
    self.* = undefined;
}

/// Insert or overwrite; the key becomes the most recently used.
pub fn put(self: *Lru, key: []const u8, value: []const u8) void {
    const hash = hashKey(key);
    if (self.find(key, hash)) |link| {
        const i = link.*;
        self.nodes[i].value = value;
        self.touch(i);
        return;
    }

    // Evicting before inserting is observably identical to inserting and
    // then evicting, and keeps the pool bounded by the capacity.
    if (self.len >= self.capacity) self.evictOldest();

    const i = self.allocNode() orelse blk: {
        // Pool exhausted: `max_entries` was underestimated. Fall back to
        // evicting the least recently used entry to make room.
        self.evictOldest();
        break :blk self.allocNode().?;
    };

    const bucket = &self.buckets[self.bucketOf(hash)];
    self.nodes[i] = .{
        .key = key,
        .value = value,
        .hash = hash,
        .prev = nil,
        .next = nil,
        .chain = bucket.*,
    };
    bucket.* = i;
    self.pushFront(i);
    self.len += 1;
}

/// Look up `key`; on a hit, mark it most recently used and return its value.
pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
    const link = self.find(key, hashKey(key)) orelse return null;
    const i = link.*;
    self.touch(i);
    return self.nodes[i].value;
}

/// Remove `key`; return whether it was present.
pub fn remove(self: *Lru, key: []const u8) bool {
    const link = self.find(key, hashKey(key)) orelse return false;
    self.release(link);
    return true;
}

pub fn count(self: *const Lru) usize {
    return self.len;
}

fn hashKey(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key);
}

fn bucketOf(self: *const Lru, hash: u64) usize {
    return @intCast(hash & (self.buckets.len - 1));
}

/// Return the link that points at the entry for `key`, so the caller can
/// both read the index and unlink it from its chain.
fn find(self: *Lru, key: []const u8, hash: u64) ?*Index {
    var link = &self.buckets[self.bucketOf(hash)];
    while (link.* != nil) {
        const node = &self.nodes[link.*];
        if (node.hash == hash and std.mem.eql(u8, node.key, key)) return link;
        link = &node.chain;
    }
    return null;
}

/// Unlink the entry `link` points at from its chain and the recency list,
/// and return its node to the free list.
fn release(self: *Lru, link: *Index) void {
    const i = link.*;
    link.* = self.nodes[i].chain;
    self.unlink(i);
    self.nodes[i].chain = self.free_head;
    self.free_head = i;
    self.len -= 1;
}

fn evictOldest(self: *Lru) void {
    const oldest = self.nodes[nil].prev;
    std.debug.assert(oldest != nil);
    var link = &self.buckets[self.bucketOf(self.nodes[oldest].hash)];
    while (link.* != oldest) link = &self.nodes[link.*].chain;
    self.release(link);
}

fn allocNode(self: *Lru) ?Index {
    if (self.free_head != nil) {
        const i = self.free_head;
        self.free_head = self.nodes[i].chain;
        return i;
    }
    if (self.pool_len + 1 < self.nodes.len) {
        self.pool_len += 1;
        return self.pool_len;
    }
    return null;
}

fn unlink(self: *Lru, i: Index) void {
    const node = &self.nodes[i];
    self.nodes[node.prev].next = node.next;
    self.nodes[node.next].prev = node.prev;
}

fn pushFront(self: *Lru, i: Index) void {
    const first = self.nodes[nil].next;
    self.nodes[i].prev = nil;
    self.nodes[i].next = first;
    self.nodes[first].prev = i;
    self.nodes[nil].next = i;
}

/// Mark entry `i` as the most recently used.
fn touch(self: *Lru, i: Index) void {
    if (self.nodes[nil].next == i) return;
    self.unlink(i);
    self.pushFront(i);
}

test "evicts least recently used" {
    var lru = try Lru.init(std.testing.allocator, 2, 16);
    defer lru.deinit(std.testing.allocator);

    lru.put("a", "1");
    lru.put("b", "2");
    try std.testing.expectEqualStrings("1", lru.get("a").?);
    lru.put("c", "3");
    try std.testing.expectEqual(null, lru.get("b"));
    try std.testing.expectEqual(2, lru.count());
}

test "overwrite refreshes recency" {
    var lru = try Lru.init(std.testing.allocator, 2, 16);
    defer lru.deinit(std.testing.allocator);

    lru.put("a", "1");
    lru.put("b", "2");
    lru.put("a", "9");
    lru.put("c", "3");
    try std.testing.expectEqualStrings("9", lru.get("a").?);
    try std.testing.expectEqual(null, lru.get("b"));
    try std.testing.expectEqualStrings("3", lru.get("c").?);
}

test "remove and reuse nodes" {
    var lru = try Lru.init(std.testing.allocator, 3, 3);
    defer lru.deinit(std.testing.allocator);

    lru.put("x", "1");
    try std.testing.expect(lru.remove("x"));
    try std.testing.expect(!lru.remove("x"));
    try std.testing.expectEqual(0, lru.count());
    lru.put("y", "2");
    lru.put("z", "3");
    lru.put("w", "4");
    lru.put("v", "5");
    try std.testing.expectEqual(3, lru.count());
    try std.testing.expectEqual(null, lru.get("y"));
}

test "pool smaller than capacity falls back to eviction" {
    var lru = try Lru.init(std.testing.allocator, 100, 2);
    defer lru.deinit(std.testing.allocator);

    lru.put("a", "1");
    lru.put("b", "2");
    lru.put("c", "3");
    try std.testing.expectEqual(2, lru.count());
    try std.testing.expectEqual(null, lru.get("a"));
}
