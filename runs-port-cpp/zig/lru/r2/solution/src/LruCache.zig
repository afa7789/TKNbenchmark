//! Fixed-capacity least-recently-used cache with O(1) expected-time operations.
//!
//! Entries live in a pool of nodes linked into a doubly linked list ordered
//! from most to least recently used; nodes are addressed by index so the pool
//! can grow without invalidating links, and freed nodes are recycled through a
//! free list. A hash map indexes keys to node indices.
//!
//! The cache does not copy keys or values: the caller must keep every slice
//! passed to `put` alive and unmodified for as long as the cache may hold it.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Node = struct {
    key: []const u8,
    value: []const u8,
    prev: Index,
    next: Index,
};

capacity: usize,
nodes: std.ArrayList(Node) = .empty,
index: std.StringHashMapUnmanaged(Index) = .empty,
/// Most recently used node, or `none` when empty.
head: Index = none,
/// Least recently used node, or `none` when empty.
tail: Index = none,
/// Head of the singly linked list (through `next`) of recycled nodes.
free: Index = none,

/// Upper bound on storage reserved up front, so an absurd capacity does not
/// commit memory that the workload may never use.
const max_reserve = 1 << 20;

pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!LruCache {
    var self: LruCache = .{ .capacity = capacity };
    errdefer self.deinit(gpa);
    const reserve: Index = @intCast(@min(capacity, max_reserve) + 1);
    try self.index.ensureTotalCapacity(gpa, reserve);
    try self.nodes.ensureTotalCapacity(gpa, reserve);
    return self;
}

pub fn deinit(self: *LruCache, gpa: Allocator) void {
    self.index.deinit(gpa);
    self.nodes.deinit(gpa);
    self.* = undefined;
}

pub fn count(self: *const LruCache) usize {
    return self.index.count();
}

/// Inserts or overwrites `key`, making it the most recently used entry.
/// Evicts the least recently used entry if capacity is exceeded.
pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    const gop = try self.index.getOrPut(gpa, key);
    if (gop.found_existing) {
        const i = gop.value_ptr.*;
        self.nodes.items[i].value = value;
        self.touch(i);
        return;
    }
    const i = self.allocNode(gpa, .{ .key = key, .value = value, .prev = none, .next = none }) catch |err| {
        self.index.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = i;
    self.pushFront(i);
    if (self.index.count() > self.capacity) self.evictOldest();
}

/// Returns the value for `key` and marks it most recently used, or null on a
/// miss.
pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
    const i = self.index.get(key) orelse return null;
    self.touch(i);
    return self.nodes.items[i].value;
}

/// Removes `key`; returns whether it was present.
pub fn remove(self: *LruCache, key: []const u8) bool {
    const kv = self.index.fetchRemove(key) orelse return false;
    self.releaseNode(kv.value);
    return true;
}

fn allocNode(self: *LruCache, gpa: Allocator, node: Node) Allocator.Error!Index {
    if (self.free != none) {
        const i = self.free;
        self.free = self.nodes.items[i].next;
        self.nodes.items[i] = node;
        return i;
    }
    if (self.nodes.items.len == none) return error.OutOfMemory;
    const i: Index = @intCast(self.nodes.items.len);
    try self.nodes.append(gpa, node);
    return i;
}

/// Unlinks node `i` from the recency list and returns it to the free list.
fn releaseNode(self: *LruCache, i: Index) void {
    self.unlink(i);
    self.nodes.items[i] = .{ .key = &.{}, .value = &.{}, .prev = none, .next = self.free };
    self.free = i;
}

fn evictOldest(self: *LruCache) void {
    const i = self.tail;
    std.debug.assert(i != none);
    _ = self.index.remove(self.nodes.items[i].key);
    self.releaseNode(i);
}

fn touch(self: *LruCache, i: Index) void {
    if (self.head == i) return;
    self.unlink(i);
    self.pushFront(i);
}

fn unlink(self: *LruCache, i: Index) void {
    const nodes = self.nodes.items;
    const node = &nodes[i];
    if (node.prev != none) nodes[node.prev].next = node.next else self.head = node.next;
    if (node.next != none) nodes[node.next].prev = node.prev else self.tail = node.prev;
    node.prev = none;
    node.next = none;
}

fn pushFront(self: *LruCache, i: Index) void {
    const nodes = self.nodes.items;
    nodes[i].prev = none;
    nodes[i].next = self.head;
    if (self.head != none) nodes[self.head].prev = i else self.tail = i;
    self.head = i;
}

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = try .init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and node reuse" {
    var cache: LruCache = try .init(testing.allocator, 3);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try cache.put(testing.allocator, "y", "2");
    try testing.expectEqual(1, cache.nodes.items.len);
    try testing.expectEqualStrings("2", cache.get("y").?);
}

test "zero capacity holds nothing" {
    var cache: LruCache = try .init(testing.allocator, 0);
    defer cache.deinit(testing.allocator);
    try cache.put(testing.allocator, "a", "1");
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("a"));
}
