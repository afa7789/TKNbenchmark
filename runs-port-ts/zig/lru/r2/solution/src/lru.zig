//! Fixed-capacity LRU (least-recently-used) cache keyed by byte strings.
//!
//! Entries live in a `std.StringArrayHashMapUnmanaged`, whose dense entry
//! array doubles as the node storage of an intrusive doubly linked list that
//! orders entries by recency. The map's index uses Robin Hood hashing with
//! backward-shift deletion, so heavy insert/delete churn never accumulates
//! tombstones and every operation stays O(1) expected.
//!
//! Keys and values are borrowed: the cache stores the slices it is given and
//! never copies them, so the caller must keep that memory alive for as long
//! as the cache may refer to it.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const LruCache = struct {
    capacity: usize,
    map: Map = .empty,
    /// Most recently used entry.
    head: Index = nil,
    /// Least recently used entry.
    tail: Index = nil,

    const Index = u32;
    const nil: Index = std.math.maxInt(Index);

    const Node = struct {
        value: []const u8,
        prev: Index,
        next: Index,
    };

    const Map = std.StringArrayHashMapUnmanaged(Node);

    /// `capacity` must be at least 1.
    pub fn init(capacity: usize) LruCache {
        std.debug.assert(capacity >= 1);
        return .{ .capacity = capacity };
    }

    pub fn deinit(self: *LruCache, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.* = undefined;
    }

    /// Preallocates room for `expected` entries (clamped to the capacity) so
    /// that subsequent insertions do not need to grow the table.
    pub fn reserve(self: *LruCache, gpa: Allocator, expected: usize) Allocator.Error!void {
        // One extra slot: an insertion briefly holds capacity + 1 entries
        // before the eviction runs.
        try self.map.ensureTotalCapacity(gpa, @min(expected, self.capacity) + 1);
    }

    pub fn count(self: *const LruCache) usize {
        return self.map.count();
    }

    /// Returns the value for `key` and marks it most recently used.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const i: Index = @intCast(self.map.getIndex(key) orelse return null);
        self.promote(i);
        return self.nodes()[i].value;
    }

    /// Inserts or overwrites `key`, making it the most recently used entry.
    /// Evicts the least recently used entry if the capacity is exceeded.
    pub fn put(self: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        const i: Index = @intCast(gop.index);
        if (gop.found_existing) {
            gop.value_ptr.value = value;
            self.promote(i);
            return;
        }
        gop.value_ptr.* = .{ .value = value, .prev = nil, .next = nil };
        self.pushFront(i);
        if (self.map.count() > self.capacity) self.removeAt(self.tail);
    }

    /// Removes `key`. Returns whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const i: Index = @intCast(self.map.getIndex(key) orelse return false);
        self.removeAt(i);
        return true;
    }

    fn nodes(self: *const LruCache) []Node {
        return self.map.values();
    }

    fn removeAt(self: *LruCache, i: Index) void {
        self.unlink(i);
        const last: Index = @intCast(self.map.count() - 1);
        self.map.swapRemoveAt(i);
        // The former last entry now occupies slot `i`; repoint its neighbours.
        if (i != last) self.relink(i);
    }

    /// Updates the neighbours of the node at `i` to refer to `i`.
    fn relink(self: *LruCache, i: Index) void {
        const ns = self.nodes();
        const node = ns[i];
        if (node.prev != nil) ns[node.prev].next = i else self.head = i;
        if (node.next != nil) ns[node.next].prev = i else self.tail = i;
    }

    fn pushFront(self: *LruCache, i: Index) void {
        const ns = self.nodes();
        ns[i].prev = nil;
        ns[i].next = self.head;
        if (self.head != nil) ns[self.head].prev = i else self.tail = i;
        self.head = i;
    }

    fn unlink(self: *LruCache, i: Index) void {
        const ns = self.nodes();
        const node = ns[i];
        if (node.prev != nil) ns[node.prev].next = node.next else self.head = node.next;
        if (node.next != nil) ns[node.next].prev = node.prev else self.tail = node.prev;
    }

    fn promote(self: *LruCache, i: Index) void {
        if (i == self.head) return;
        self.unlink(i);
        self.pushFront(i);
    }
};

const testing = std.testing;

test "evicts least recently used" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache: LruCache = .init(2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove keeps list consistent after slot relocation" {
    var cache: LruCache = .init(3);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "c", "3");
    try testing.expect(cache.remove("a"));
    try testing.expect(!cache.remove("a"));
    try cache.put(testing.allocator, "d", "4");
    try cache.put(testing.allocator, "e", "5");
    // Order (MRU first): e d c — "b" was evicted.
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
    try cache.put(testing.allocator, "f", "6");
    try testing.expectEqual(null, cache.get("d"));
    try testing.expectEqual(3, cache.count());
}

test "matches a reference model under random churn" {
    const gpa = testing.allocator;
    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();

    const key_names = [_][]const u8{ "k0", "k1", "k2", "k3", "k4", "k5", "k6", "k7", "k8", "k9" };
    const capacity = 4;
    var cache: LruCache = .init(capacity);
    defer cache.deinit(gpa);

    // Reference: keys ordered from least to most recently used.
    var order: std.ArrayList(usize) = .empty;
    defer order.deinit(gpa);

    for (0..20_000) |_| {
        const k = random.uintLessThan(usize, key_names.len);
        const pos = std.mem.indexOfScalar(usize, order.items, k);
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                try cache.put(gpa, key_names[k], key_names[k]);
                if (pos) |p| _ = order.orderedRemove(p);
                try order.append(gpa, k);
                if (order.items.len > capacity) _ = order.orderedRemove(0);
            },
            1 => {
                const got = cache.get(key_names[k]);
                try testing.expectEqual(pos != null, got != null);
                if (pos) |p| {
                    _ = order.orderedRemove(p);
                    try order.append(gpa, k);
                }
            },
            else => {
                try testing.expectEqual(pos != null, cache.remove(key_names[k]));
                if (pos) |p| _ = order.orderedRemove(p);
            },
        }
        try testing.expectEqual(order.items.len, cache.count());
    }
}
