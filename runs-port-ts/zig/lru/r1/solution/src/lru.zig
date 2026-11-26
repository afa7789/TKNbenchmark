//! A fixed-capacity least-recently-used cache keyed by byte strings.
//!
//! Entries live in a `std.StringArrayHashMapUnmanaged`, whose dense entry
//! array doubles as the node pool of an intrusive doubly linked list ordered
//! from least to most recently used. The map's index uses backward-shift
//! deletion, so heavy insert/delete churn never accumulates tombstones and
//! every operation stays O(1) expected time.
//!
//! The cache does not copy keys or values; callers must keep the referenced
//! memory alive for as long as the cache holds it.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn LruCache(comptime V: type) type {
    return struct {
        const Self = @This();

        /// Sentinel link meaning "no neighbor".
        const none = std.math.maxInt(u32);

        const Node = struct {
            value: V,
            /// Neighbor toward the least recently used end.
            prev: u32,
            /// Neighbor toward the most recently used end.
            next: u32,
        };

        const Map = std.StringArrayHashMapUnmanaged(Node);

        map: Map = .empty,
        capacity: u32,
        /// Least recently used entry.
        head: u32 = none,
        /// Most recently used entry.
        tail: u32 = none,

        pub fn init(capacity: u32) Self {
            std.debug.assert(capacity >= 1);
            return .{ .capacity = capacity };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.map.deinit(gpa);
            self.* = undefined;
        }

        pub fn count(self: *const Self) usize {
            return self.map.count();
        }

        /// Returns the value for `key` and marks it most recently used.
        pub fn get(self: *Self, key: []const u8) ?V {
            const index: u32 = @intCast(self.map.getIndex(key) orelse return null);
            self.moveToTail(index);
            return self.nodes()[index].value;
        }

        /// Inserts or overwrites `key`, marking it most recently used and
        /// evicting the least recently used entry if over capacity.
        pub fn put(self: *Self, gpa: Allocator, key: []const u8, value: V) Allocator.Error!void {
            const gop = try self.map.getOrPut(gpa, key);
            const index: u32 = @intCast(gop.index);
            if (gop.found_existing) {
                gop.value_ptr.value = value;
                self.moveToTail(index);
                return;
            }
            gop.value_ptr.* = .{ .value = value, .prev = none, .next = none };
            self.linkAtTail(index);
            if (self.map.count() > self.capacity) self.removeAt(self.head);
        }

        /// Removes `key`; returns whether it was present.
        pub fn remove(self: *Self, key: []const u8) bool {
            const index = self.map.getIndex(key) orelse return false;
            self.removeAt(@intCast(index));
            return true;
        }

        fn nodes(self: *const Self) []Node {
            return self.map.values();
        }

        fn unlink(self: *Self, index: u32) void {
            const n = self.nodes();
            const node = n[index];
            if (node.prev == none) self.head = node.next else n[node.prev].next = node.next;
            if (node.next == none) self.tail = node.prev else n[node.next].prev = node.prev;
        }

        fn linkAtTail(self: *Self, index: u32) void {
            const n = self.nodes();
            n[index].prev = self.tail;
            n[index].next = none;
            if (self.tail == none) self.head = index else n[self.tail].next = index;
            self.tail = index;
        }

        fn moveToTail(self: *Self, index: u32) void {
            if (index == self.tail) return;
            self.unlink(index);
            self.linkAtTail(index);
        }

        /// Removes the entry at `index`. The map fills the hole with its last
        /// entry, so that entry's neighbors are repointed at its new index.
        fn removeAt(self: *Self, index: u32) void {
            self.unlink(index);
            const last: u32 = @intCast(self.map.count() - 1);
            self.map.swapRemoveAt(index);
            if (index == last) return;

            const n = self.nodes();
            const moved = n[index];
            if (moved.prev == none) self.head = index else n[moved.prev].next = index;
            if (moved.next == none) self.tail = index else n[moved.next].prev = index;
        }
    };
}

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache([]const u8) = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache([]const u8) = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove reports presence" {
    var cache: LruCache(u32) = .init(3);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "x", 1);
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("x"));
}

test "matches a reference model under churn" {
    const gpa = testing.allocator;
    const capacity = 7;
    var cache: LruCache(u32) = .init(capacity);
    defer cache.deinit(gpa);

    // Reference: keys ordered from least to most recently used.
    var order: std.ArrayList(u8) = .empty;
    defer order.deinit(gpa);
    var values: [16]u32 = undefined;

    const names = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f" };
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();

    for (0..20_000) |step| {
        const k = random.uintLessThan(u8, names.len);
        const pos = std.mem.indexOfScalar(u8, order.items, k);
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const v: u32 = @intCast(step);
                try cache.put(gpa, names[k], v);
                values[k] = v;
                if (pos) |p| _ = order.orderedRemove(p);
                try order.append(gpa, k);
                if (order.items.len > capacity) _ = order.orderedRemove(0);
            },
            1 => {
                const got = cache.get(names[k]);
                if (pos) |p| {
                    try testing.expectEqual(values[k], got.?);
                    _ = order.orderedRemove(p);
                    try order.append(gpa, k);
                } else try testing.expectEqual(null, got);
            },
            else => {
                try testing.expectEqual(pos != null, cache.remove(names[k]));
                if (pos) |p| _ = order.orderedRemove(p);
            },
        }
        try testing.expectEqual(order.items.len, cache.count());
    }
}
