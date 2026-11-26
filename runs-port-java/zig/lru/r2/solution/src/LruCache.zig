//! A fixed-capacity cache keyed by byte strings that evicts the least
//! recently used entry. All operations run in O(1) expected time.
//!
//! Entries are stored densely in an array hash map and threaded onto a doubly
//! linked recency list by entry index (most recent at the head). The array
//! hash map deletes without tombstones, so lookups stay fast under heavy
//! eviction churn; removal swaps the last entry into the freed slot, and the
//! moved entry's neighbours are relinked to its new index.
//!
//! Keys and values are borrowed: the caller must keep their memory alive for
//! as long as they are held by the cache.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

const Index = u32;
const none: Index = std.math.maxInt(Index);

/// Upper bound on what `init` preallocates, so huge capacities that are never
/// filled do not cost memory up front.
const max_initial_capacity = 1 << 16;

const Entry = struct {
    value: []const u8,
    /// Neighbour towards the most recently used end, or `none`.
    prev: Index,
    /// Neighbour towards the least recently used end, or `none`.
    next: Index,
};

/// Maximum number of entries; at least 1.
capacity: u32,
map: std.StringArrayHashMapUnmanaged(Entry),
/// Most recently used entry, or `none` when empty.
head: Index,
/// Least recently used entry, or `none` when empty.
tail: Index,

pub const InitError = Allocator.Error || error{InvalidCapacity};

pub fn init(gpa: Allocator, capacity: u32) InitError!LruCache {
    // One spare index is needed for the entry inserted just before an eviction.
    if (capacity == 0 or capacity >= none) return error.InvalidCapacity;
    var map: std.StringArrayHashMapUnmanaged(Entry) = .empty;
    try map.ensureTotalCapacity(gpa, @min(capacity, max_initial_capacity) + 1);
    return .{ .capacity = capacity, .map = map, .head = none, .tail = none };
}

pub fn deinit(self: *LruCache, gpa: Allocator) void {
    self.map.deinit(gpa);
    self.* = undefined;
}

/// Number of entries held.
pub fn count(self: *const LruCache) u32 {
    return @intCast(self.map.count());
}

/// Inserts or overwrites a mapping, making the key the most recently used.
/// Evicts the least recently used entry if the cache then exceeds capacity.
pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    const gop = try self.map.getOrPut(gpa, key);
    const index: Index = @intCast(gop.index);
    if (gop.found_existing) {
        gop.value_ptr.value = value;
        self.moveToFront(index);
        return;
    }
    gop.value_ptr.* = .{ .value = value, .prev = none, .next = none };
    self.linkFront(index);
    if (self.map.count() > self.capacity) self.removeAt(self.tail);
}

/// Returns the value for the key, marking it most recently used, or null if absent.
pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
    const index: Index = @intCast(self.map.getIndex(key) orelse return null);
    self.moveToFront(index);
    return self.map.values()[index].value;
}

/// Removes the key, returning whether it was present.
pub fn remove(self: *LruCache, key: []const u8) bool {
    const index: Index = @intCast(self.map.getIndex(key) orelse return false);
    self.removeAt(index);
    return true;
}

fn removeAt(self: *LruCache, index: Index) void {
    self.unlink(index);
    self.map.swapRemoveAt(index);
    // The former last entry now occupies `index`; point its neighbours at it.
    if (index == self.map.count()) return;
    const entries = self.map.values();
    const moved = entries[index];
    if (moved.prev == none) self.head = index else entries[moved.prev].next = index;
    if (moved.next == none) self.tail = index else entries[moved.next].prev = index;
}

fn moveToFront(self: *LruCache, index: Index) void {
    if (self.head == index) return;
    self.unlink(index);
    self.linkFront(index);
}

fn unlink(self: *LruCache, index: Index) void {
    const entries = self.map.values();
    const entry = entries[index];
    if (entry.prev == none) self.head = entry.next else entries[entry.prev].next = entry.next;
    if (entry.next == none) self.tail = entry.prev else entries[entry.next].prev = entry.prev;
}

fn linkFront(self: *LruCache, index: Index) void {
    const entries = self.map.values();
    entries[index].prev = none;
    entries[index].next = self.head;
    if (self.head == none) self.tail = index else entries[self.head].prev = index;
    self.head = index;
}

const testing = std.testing;

/// Checks that the recency list is consistent and lists keys from most to
/// least recently used.
fn expectOrder(cache: *const LruCache, expected: []const []const u8) !void {
    const keys = cache.map.keys();
    const entries = cache.map.values();
    try testing.expectEqual(expected.len, keys.len);
    var prev = none;
    var index = cache.head;
    for (expected) |key| {
        try testing.expect(index != none);
        try testing.expectEqualStrings(key, keys[index]);
        try testing.expectEqual(prev, entries[index].prev);
        prev = index;
        index = entries[index].next;
    }
    try testing.expectEqual(none, index);
    try testing.expectEqual(prev, cache.tail);
}

test "evicts the least recently used key" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expect(cache.get("b") == null);
    try expectOrder(&cache, &.{ "c", "a" });
    try testing.expectEqualStrings("1", cache.get("a").?);
    try testing.expectEqualStrings("3", cache.get("c").?);
    try expectOrder(&cache, &.{ "c", "a" });
}

test "overwrite refreshes recency" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expect(cache.get("b") == null);
    try expectOrder(&cache, &.{ "a", "c" });
}

test "remove relinks the entry moved into the freed slot" {
    var cache: LruCache = try .init(testing.allocator, 4);
    defer cache.deinit(testing.allocator);

    for ([_][]const u8{ "a", "b", "c", "d" }) |key| try cache.put(testing.allocator, key, key);
    try expectOrder(&cache, &.{ "d", "c", "b", "a" });
    try testing.expect(cache.remove("b"));
    try expectOrder(&cache, &.{ "d", "c", "a" });
    try testing.expect(cache.remove("d"));
    try expectOrder(&cache, &.{ "c", "a" });
    try testing.expect(!cache.remove("d"));
    try testing.expect(cache.remove("a"));
    try testing.expect(cache.remove("c"));
    try expectOrder(&cache, &.{});
    try cache.put(testing.allocator, "e", "5");
    try expectOrder(&cache, &.{"e"});
}

test "capacity one" {
    var cache: LruCache = try .init(testing.allocator, 1);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expect(cache.get("a") == null);
    try testing.expectEqualStrings("2", cache.get("b").?);
    try expectOrder(&cache, &.{"b"});
}

test "rejects zero capacity" {
    try testing.expectError(error.InvalidCapacity, LruCache.init(testing.allocator, 0));
}
