//! A least-recently-used cache mapping byte-string keys to byte-string values.
//!
//! Entries are stored densely in an array hash map and threaded, by entry
//! index, into a doubly linked recency list (head = least recently used,
//! tail = most recently used). Removal swaps the last entry into the vacated
//! slot and patches its neighbours' links. The map deletes without
//! tombstones, so lookup cost stays flat under heavy insert/delete churn.
//! Every operation runs in O(1) expected time.
//!
//! The cache does not own key or value memory: slices passed to `put` must
//! outlive the cache (or their entry).

const std = @import("std");
const Allocator = std.mem.Allocator;

const Lru = @This();

const Index = u32;
const none: Index = std.math.maxInt(Index);

const Entry = struct {
    value: []const u8,
    prev: Index,
    next: Index,
};

map: std.StringArrayHashMapUnmanaged(Entry) = .empty,
head: Index = none,
tail: Index = none,
capacity: usize,

pub fn init(capacity: usize) Lru {
    return .{ .capacity = capacity };
}

pub fn deinit(self: *Lru, gpa: Allocator) void {
    self.map.deinit(gpa);
    self.* = undefined;
}

/// Pre-allocates room for `n` entries so that inserts up to that count do not
/// reallocate.
pub fn ensureTotalCapacity(self: *Lru, gpa: Allocator, n: usize) Allocator.Error!void {
    try self.map.ensureTotalCapacity(gpa, n);
}

pub fn count(self: *const Lru) usize {
    return self.map.count();
}

/// Returns the value for `key` and marks it most recently used.
pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
    const index = self.map.getIndex(key) orelse return null;
    self.touch(@intCast(index));
    return self.entries()[index].value;
}

/// Inserts or overwrites `key`, marking it most recently used. Evicts the
/// least recently used entry if the cache then exceeds its capacity.
pub fn put(self: *Lru, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
    if (self.capacity == 0) return;
    if (self.map.count() >= none) return error.OutOfMemory;

    const gop = try self.map.getOrPut(gpa, key);
    const index: Index = @intCast(gop.index);
    if (gop.found_existing) {
        gop.value_ptr.value = value;
        self.touch(index);
        return;
    }

    gop.value_ptr.* = .{ .value = value, .prev = none, .next = none };
    self.pushBack(index);

    if (self.map.count() > self.capacity) {
        std.debug.assert(self.head != index);
        self.removeAt(self.head);
    }
}

/// Removes `key`; returns whether it was present.
pub fn remove(self: *Lru, key: []const u8) bool {
    const index = self.map.getIndex(key) orelse return false;
    self.removeAt(@intCast(index));
    return true;
}

fn entries(self: *const Lru) []Entry {
    return self.map.values();
}

fn removeAt(self: *Lru, index: Index) void {
    self.unlink(index);
    const last: Index = @intCast(self.map.count() - 1);
    self.map.swapRemoveAt(index);
    if (index == last) return;

    // The former last entry now lives at `index`; redirect links to it.
    const nodes = self.entries();
    const moved = nodes[index];
    if (moved.prev != none) nodes[moved.prev].next = index else self.head = index;
    if (moved.next != none) nodes[moved.next].prev = index else self.tail = index;
}

fn touch(self: *Lru, index: Index) void {
    if (index == self.tail) return;
    self.unlink(index);
    self.pushBack(index);
}

fn unlink(self: *Lru, index: Index) void {
    const nodes = self.entries();
    const node = &nodes[index];
    if (node.prev != none) nodes[node.prev].next = node.next else self.head = node.next;
    if (node.next != none) nodes[node.next].prev = node.prev else self.tail = node.prev;
    node.prev = none;
    node.next = none;
}

fn pushBack(self: *Lru, index: Index) void {
    const nodes = self.entries();
    nodes[index].prev = self.tail;
    nodes[index].next = none;
    if (self.tail != none) nodes[self.tail].next = index else self.head = index;
    self.tail = index;
}

const testing = std.testing;

test "evicts least recently used" {
    var lru: Lru = .init(2);
    defer lru.deinit(testing.allocator);

    try lru.put(testing.allocator, "a", "1");
    try lru.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", lru.get("a").?);
    try lru.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, lru.get("b"));
    try testing.expectEqualStrings("1", lru.get("a").?);
    try testing.expectEqualStrings("3", lru.get("c").?);
    try testing.expectEqual(2, lru.count());
}

test "overwrite refreshes recency" {
    var lru: Lru = .init(2);
    defer lru.deinit(testing.allocator);

    try lru.put(testing.allocator, "a", "1");
    try lru.put(testing.allocator, "b", "2");
    try lru.put(testing.allocator, "a", "9");
    try lru.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", lru.get("a").?);
    try testing.expectEqual(null, lru.get("b"));
}

test "remove keeps recency order of moved entries" {
    var lru: Lru = .init(3);
    defer lru.deinit(testing.allocator);

    try lru.put(testing.allocator, "x", "1");
    try lru.put(testing.allocator, "y", "2");
    try lru.put(testing.allocator, "z", "3");
    // Removing "x" moves "z" into its slot; order must stay y, z.
    try testing.expect(lru.remove("x"));
    try testing.expect(!lru.remove("x"));
    try lru.put(testing.allocator, "w", "4");
    try lru.put(testing.allocator, "v", "5");
    try testing.expectEqual(null, lru.get("y"));
    try testing.expectEqualStrings("3", lru.get("z").?);
    try testing.expectEqual(3, lru.count());
}

test "zero capacity holds nothing" {
    var lru: Lru = .init(0);
    defer lru.deinit(testing.allocator);

    try lru.put(testing.allocator, "a", "1");
    try testing.expectEqual(0, lru.count());
    try testing.expectEqual(null, lru.get("a"));
}
