//! A fixed-capacity string cache that evicts the least recently used entry.
//!
//! Keys and values are borrowed: the cache stores the slices it is given and
//! never copies them, so the caller must keep the backing memory alive for as
//! long as the cache is in use. Every operation runs in O(1) expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

/// Position of an entry in the map's dense entry array.
const Index = u32;
const nil: Index = std.math.maxInt(Index);

/// The recency list is threaded through the map's entries by index.
/// Removal uses swap-remove, so the moved entry's neighbours are re-pointed.
const Entry = struct {
    value: []const u8,
    /// Neighbour towards the most recently used end.
    prev: Index,
    /// Neighbour towards the least recently used end.
    next: Index,
};

/// An insertion-ordered map whose deletions use backward shifting rather
/// than tombstones, keeping probe lengths short under constant churn.
const Map = std.StringArrayHashMapUnmanaged(Entry);

capacity: Index,
map: Map,
/// Most recently used entry.
head: Index,
/// Least recently used entry.
tail: Index,

pub const InitError = Allocator.Error || error{InvalidCapacity};

/// Upper bound on storage reserved up front, so that a huge capacity paired
/// with a short command stream does not allocate needlessly.
const max_preallocated = 1 << 16;

pub fn init(gpa: Allocator, capacity: usize) InitError!LruCache {
    if (capacity == 0 or capacity >= nil) return error.InvalidCapacity;
    var map: Map = .empty;
    try map.ensureTotalCapacity(gpa, @min(capacity, max_preallocated));
    return .{
        .capacity = @intCast(capacity),
        .map = map,
        .head = nil,
        .tail = nil,
    };
}

pub fn deinit(cache: *LruCache, gpa: Allocator) void {
    cache.map.deinit(gpa);
    cache.* = undefined;
}

/// Number of keys currently held.
pub fn count(cache: *const LruCache) usize {
    return cache.map.count();
}

/// Inserts or overwrites a mapping and marks the key as most recently used,
/// evicting the least recently used key if the cache would exceed capacity.
pub fn set(cache: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    if (cache.map.getIndex(key)) |i| {
        const index: Index = @intCast(i);
        cache.entries()[index].value = value;
        cache.promote(index);
        return;
    }

    // Reserve space before touching any state so a failed allocation leaves
    // the cache unchanged.
    try cache.map.ensureUnusedCapacity(gpa, 1);
    if (cache.map.count() == cache.capacity) cache.removeAt(cache.tail);

    const index: Index = @intCast(cache.map.count());
    cache.map.putAssumeCapacityNoClobber(key, .{ .value = value, .prev = nil, .next = nil });
    cache.pushFront(index);
}

/// Returns the value stored for `key`, marking it most recently used, or
/// `null` if the key is absent.
pub fn get(cache: *LruCache, key: []const u8) ?[]const u8 {
    const index: Index = @intCast(cache.map.getIndex(key) orelse return null);
    cache.promote(index);
    return cache.entries()[index].value;
}

/// Removes `key`; returns whether it was present.
pub fn remove(cache: *LruCache, key: []const u8) bool {
    const index: Index = @intCast(cache.map.getIndex(key) orelse return false);
    cache.removeAt(index);
    return true;
}

fn entries(cache: *const LruCache) []Entry {
    return cache.map.values();
}

fn removeAt(cache: *LruCache, index: Index) void {
    cache.unlink(index);
    const last: Index = @intCast(cache.map.count() - 1);
    cache.map.swapRemoveAt(index);
    if (index == last) return;

    // The former last entry now lives at `index`; re-point its neighbours.
    const moved = cache.entries()[index];
    if (moved.prev != nil) cache.entries()[moved.prev].next = index else cache.head = index;
    if (moved.next != nil) cache.entries()[moved.next].prev = index else cache.tail = index;
}

fn promote(cache: *LruCache, index: Index) void {
    if (cache.head == index) return;
    cache.unlink(index);
    cache.pushFront(index);
}

fn pushFront(cache: *LruCache, index: Index) void {
    const entry = &cache.entries()[index];
    entry.prev = nil;
    entry.next = cache.head;
    if (cache.head != nil) cache.entries()[cache.head].prev = index else cache.tail = index;
    cache.head = index;
}

fn unlink(cache: *LruCache, index: Index) void {
    const entry = cache.entries()[index];
    if (entry.prev != nil) cache.entries()[entry.prev].next = entry.next else cache.head = entry.next;
    if (entry.next != nil) cache.entries()[entry.next].prev = entry.prev else cache.tail = entry.prev;
}

const testing = std.testing;

test "evicts the least recently used key" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try cache.set(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.set(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try cache.set(testing.allocator, "b", "2");
    try cache.set(testing.allocator, "a", "9");
    try cache.set(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove frees a slot for reuse" {
    var cache: LruCache = try .init(testing.allocator, 1);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try cache.set(testing.allocator, "y", "2");
    try testing.expectEqualStrings("2", cache.get("y").?);
}

test "swap-removal keeps recency order intact" {
    var cache: LruCache = try .init(testing.allocator, 3);
    defer cache.deinit(testing.allocator);

    try cache.set(testing.allocator, "a", "1");
    try cache.set(testing.allocator, "b", "2");
    try cache.set(testing.allocator, "c", "3");
    _ = cache.get("a"); // order (MRU..LRU): a c b
    try testing.expect(cache.remove("a")); // "c" is swapped into slot 0
    try cache.set(testing.allocator, "d", "4"); // d c b
    try cache.set(testing.allocator, "e", "5"); // evicts b
    try testing.expectEqual(null, cache.get("b"));
    try cache.set(testing.allocator, "f", "6"); // evicts c
    try testing.expectEqual(null, cache.get("c"));
    try testing.expectEqualStrings("4", cache.get("d").?);
    try testing.expectEqualStrings("5", cache.get("e").?);
    try testing.expectEqualStrings("6", cache.get("f").?);
}

test "rejects zero capacity" {
    try testing.expectError(error.InvalidCapacity, LruCache.init(testing.allocator, 0));
}
