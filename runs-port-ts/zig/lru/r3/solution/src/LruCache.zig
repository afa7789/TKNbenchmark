//! Fixed-capacity LRU cache with O(1) expected-time operations.
//!
//! Entries are stored densely in an array hash map, whose index uses
//! backward-shift deletion and so does not degrade under heavy churn the way a
//! tombstoning map would. Recency order is an intrusive doubly linked list
//! threaded through the entries by position; when a removal swaps the last
//! entry into the vacated position, that entry's neighbours are re-pointed.
//!
//! Keys and values are borrowed: the cache stores the slices it is given and
//! never copies or frees them. Callers must keep that memory alive for as long
//! as the cache may reference it.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

/// Position of an entry in `map`.
const Index = u32;
const nil: Index = std.math.maxInt(Index);

const Node = struct {
    value: []const u8,
    /// Neighbour towards the most recently used end.
    prev: Index,
    /// Neighbour towards the least recently used end.
    next: Index,
};

capacity: usize,
map: std.StringArrayHashMapUnmanaged(Node) = .empty,
/// Most recently used entry.
head: Index = nil,
/// Least recently used entry.
tail: Index = nil,

pub const InitError = Allocator.Error || error{InvalidCapacity};

/// Creates an empty cache. `expected_entries` is a sizing hint used to
/// preallocate storage (clamped to `capacity`); pass 0 to grow on demand.
pub fn init(gpa: Allocator, capacity: usize, expected_entries: usize) InitError!LruCache {
    if (capacity < 1 or capacity >= nil) return error.InvalidCapacity;
    var cache: LruCache = .{ .capacity = capacity };
    try cache.map.ensureTotalCapacity(gpa, @min(capacity, expected_entries));
    return cache;
}

pub fn deinit(self: *LruCache, gpa: Allocator) void {
    self.map.deinit(gpa);
    self.* = undefined;
}

/// Number of keys currently held.
pub fn count(self: *const LruCache) usize {
    return self.map.count();
}

/// Returns the value for `key` and marks it most recently used, or null on a miss.
pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
    const index = self.indexOf(key) orelse return null;
    self.moveToFront(index);
    return self.nodes()[index].value;
}

/// Inserts or overwrites `key`, making it the most recently used entry.
/// Evicts the least recently used entry if the cache would exceed capacity.
pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    if (self.indexOf(key)) |index| {
        self.nodes()[index].value = value;
        self.moveToFront(index);
        return;
    }

    // Reserve before evicting so a failed allocation leaves the cache intact.
    try self.map.ensureUnusedCapacity(gpa, 1);
    if (self.map.count() >= self.capacity) self.removeAt(self.tail);

    const gop = self.map.getOrPutAssumeCapacity(key);
    std.debug.assert(!gop.found_existing);
    gop.value_ptr.* = .{ .value = value, .prev = nil, .next = nil };
    self.pushFront(@intCast(gop.index));
}

/// Removes `key`. Returns whether it was present.
pub fn remove(self: *LruCache, key: []const u8) bool {
    const index = self.indexOf(key) orelse return false;
    self.removeAt(index);
    return true;
}

fn indexOf(self: *const LruCache, key: []const u8) ?Index {
    const index = self.map.getIndex(key) orelse return null;
    return @intCast(index);
}

fn nodes(self: *const LruCache) []Node {
    return self.map.values();
}

fn removeAt(self: *LruCache, index: Index) void {
    self.unlink(index);
    self.map.swapRemoveAt(index);
    // The former last entry, if any, now lives at `index`; re-point its neighbours.
    if (index == self.map.count()) return;
    const moved = self.nodes()[index];
    if (moved.prev != nil) self.nodes()[moved.prev].next = index else self.head = index;
    if (moved.next != nil) self.nodes()[moved.next].prev = index else self.tail = index;
}

fn moveToFront(self: *LruCache, index: Index) void {
    if (index == self.head) return;
    self.unlink(index);
    self.pushFront(index);
}

fn pushFront(self: *LruCache, index: Index) void {
    const all = self.nodes();
    all[index].prev = nil;
    all[index].next = self.head;
    if (self.head != nil) all[self.head].prev = index;
    self.head = index;
    if (self.tail == nil) self.tail = index;
}

fn unlink(self: *LruCache, index: Index) void {
    const all = self.nodes();
    const prev = all[index].prev;
    const next = all[index].next;
    if (prev != nil) all[prev].next = next else self.head = next;
    if (next != nil) all[next].prev = prev else self.tail = prev;
}

const testing = std.testing;

test "evicts the least recently used key" {
    var cache: LruCache = try .init(testing.allocator, 2, 0);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = try .init(testing.allocator, 2, 0);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove frees slots for reuse" {
    var cache: LruCache = try .init(testing.allocator, 3, 3);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    for ([_][]const u8{ "p", "q", "r", "s" }) |k| try cache.put(testing.allocator, k, k);
    try testing.expectEqual(3, cache.count());
    try testing.expectEqual(null, cache.get("p"));
    try testing.expectEqualStrings("q", cache.get("q").?);
    try testing.expect(cache.remove("r"));
    try cache.put(testing.allocator, "t", "t");
    try cache.put(testing.allocator, "u", "u");
    try testing.expectEqual(null, cache.get("s"));
    try testing.expectEqualStrings("q", cache.get("q").?);
    try testing.expectEqualStrings("t", cache.get("t").?);
    try testing.expectEqualStrings("u", cache.get("u").?);
}

test "capacity one" {
    var cache: LruCache = try .init(testing.allocator, 1, 0);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqual(null, cache.get("a"));
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.count());
}

test "rejects zero capacity" {
    try testing.expectError(error.InvalidCapacity, LruCache.init(testing.allocator, 0, 0));
}
