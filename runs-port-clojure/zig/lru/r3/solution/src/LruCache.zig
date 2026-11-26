//! A fixed-capacity least-recently-used cache mapping short byte-string keys
//! to short byte-string values.
//!
//! Entries live in a slot array and are threaded onto an intrusive doubly
//! linked recency list by index. The hash map stores only slot indices and
//! hashes them through the key bytes held in the slot, so each key is stored
//! exactly once. Every operation runs in O(1) expected time.

const std = @import("std");
const Allocator = std.mem.Allocator;

const LruCache = @This();

/// Longest key or value, in bytes, that the cache can hold.
pub const max_len = 64;

const Index = u32;

/// Slot 0 is the sentinel of the circular recency list: `sentinel.next` is the
/// most recently used entry and `sentinel.prev` the least recently used one.
const sentinel: Index = 0;
/// Terminates the free-slot list.
const none: Index = std.math.maxInt(Index);

const Slot = struct {
    prev: Index,
    /// Recency-list successor while in use; free-list successor otherwise.
    next: Index,
    key_len: u8,
    value_len: u8,
    key_buf: [max_len]u8,
    value_buf: [max_len]u8,

    fn key(slot: *const Slot) []const u8 {
        return slot.key_buf[0..slot.key_len];
    }

    fn value(slot: *const Slot) []const u8 {
        return slot.value_buf[0..slot.value_len];
    }

    fn setKey(slot: *Slot, bytes: []const u8) void {
        @memcpy(slot.key_buf[0..bytes.len], bytes);
        slot.key_len = @intCast(bytes.len);
    }

    fn setValue(slot: *Slot, bytes: []const u8) void {
        @memcpy(slot.value_buf[0..bytes.len], bytes);
        slot.value_len = @intCast(bytes.len);
    }
};

fn hashKey(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0, key);
}

/// Hashes stored slot indices by the key bytes they hold.
const IndexContext = struct {
    slots: []const Slot,

    pub fn hash(ctx: IndexContext, index: Index) u64 {
        return hashKey(ctx.slots[index].key());
    }

    pub fn eql(_: IndexContext, a: Index, b: Index) bool {
        return a == b;
    }
};

/// Lets the map be queried with a key slice instead of a slot index.
const KeyAdapter = struct {
    slots: []const Slot,

    pub fn hash(_: KeyAdapter, key: []const u8) u64 {
        return hashKey(key);
    }

    pub fn eql(ctx: KeyAdapter, key: []const u8, index: Index) bool {
        return std.mem.eql(u8, key, ctx.slots[index].key());
    }
};

const Map = std.HashMapUnmanaged(Index, void, IndexContext, std.hash_map.default_max_load_percentage);

pub const Error = Allocator.Error || error{ KeyTooLong, ValueTooLong };

capacity: usize,
slots: std.ArrayList(Slot),
map: Map,
free_head: Index,
/// Removals since the map was last rehashed; an upper bound on its tombstones.
removals: usize,

pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!LruCache {
    var slots: std.ArrayList(Slot) = .empty;
    try slots.append(gpa, .{
        .prev = sentinel,
        .next = sentinel,
        .key_len = 0,
        .value_len = 0,
        .key_buf = undefined,
        .value_buf = undefined,
    });
    return .{ .capacity = capacity, .slots = slots, .map = .empty, .free_head = none, .removals = 0 };
}

pub fn deinit(cache: *LruCache, gpa: Allocator) void {
    cache.map.deinit(gpa);
    cache.slots.deinit(gpa);
    cache.* = undefined;
}

/// Number of entries currently held.
pub fn count(cache: *const LruCache) usize {
    return cache.map.count();
}

/// Returns the value stored under `key` and marks it most recently used.
/// The returned slice is valid until the next mutating call.
pub fn get(cache: *LruCache, key: []const u8) ?[]const u8 {
    const index = cache.find(key) orelse return null;
    cache.unlink(index);
    cache.pushFront(index);
    return cache.slots.items[index].value();
}

/// Inserts or overwrites `key`, marks it most recently used, and evicts the
/// least recently used entry if the cache then exceeds its capacity.
pub fn put(cache: *LruCache, gpa: Allocator, key: []const u8, value: []const u8) Error!void {
    if (key.len > max_len) return error.KeyTooLong;
    if (value.len > max_len) return error.ValueTooLong;

    // Reserve a slot up front so nothing can fail once the map entry exists.
    try cache.slots.ensureUnusedCapacity(gpa, 1);
    const gop = try cache.map.getOrPutContextAdapted(
        gpa,
        key,
        KeyAdapter{ .slots = cache.slots.items },
        IndexContext{ .slots = cache.slots.items },
    );

    if (gop.found_existing) {
        const index = gop.key_ptr.*;
        cache.slots.items[index].setValue(value);
        cache.unlink(index);
        cache.pushFront(index);
        return;
    }

    const index = cache.acquireSlot();
    gop.key_ptr.* = index;
    const slot = &cache.slots.items[index];
    slot.setKey(key);
    slot.setValue(value);
    cache.pushFront(index);

    if (cache.map.count() > cache.capacity) {
        const lru = cache.slots.items[sentinel].prev;
        cache.evict(lru);
    }
}

/// Removes `key`. Returns whether it was present.
pub fn remove(cache: *LruCache, key: []const u8) bool {
    const index = cache.find(key) orelse return false;
    cache.evict(index);
    return true;
}

/// Drops the entry in slot `index` from the list and the map.
fn evict(cache: *LruCache, index: Index) void {
    cache.unlink(index);
    const removed = cache.map.removeContext(index, cache.indexContext());
    std.debug.assert(removed);
    cache.releaseSlot(index);

    // The map deletes with tombstones and never reclaims them on its own, so
    // under steady churn misses would probe ever longer. Rehashing once
    // removals reach a fraction of the table keeps probes short at amortized
    // O(1) cost per removal.
    cache.removals += 1;
    if (cache.removals > cache.map.capacity() / 4) {
        cache.map.rehash(cache.indexContext());
        cache.removals = 0;
    }
}

fn find(cache: *const LruCache, key: []const u8) ?Index {
    if (key.len > max_len) return null;
    const adapter: KeyAdapter = .{ .slots = cache.slots.items };
    return cache.map.getKeyAdapted(key, adapter);
}

fn indexContext(cache: *const LruCache) IndexContext {
    return .{ .slots = cache.slots.items };
}

/// Takes a slot from the free list or appends one; capacity must already be
/// reserved.
fn acquireSlot(cache: *LruCache) Index {
    if (cache.free_head != none) {
        const index = cache.free_head;
        cache.free_head = cache.slots.items[index].next;
        return index;
    }
    const index: Index = @intCast(cache.slots.items.len);
    cache.slots.appendAssumeCapacity(undefined);
    return index;
}

fn releaseSlot(cache: *LruCache, index: Index) void {
    cache.slots.items[index].next = cache.free_head;
    cache.free_head = index;
}

fn unlink(cache: *LruCache, index: Index) void {
    const slots = cache.slots.items;
    const slot = &slots[index];
    slots[slot.prev].next = slot.next;
    slots[slot.next].prev = slot.prev;
}

fn pushFront(cache: *LruCache, index: Index) void {
    const slots = cache.slots.items;
    const first = slots[sentinel].next;
    slots[index].prev = sentinel;
    slots[index].next = first;
    slots[first].prev = index;
    slots[sentinel].next = index;
}

const testing = std.testing;

test "evicts the least recently used entry" {
    var cache = try LruCache.init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqualStrings("1", cache.get("a").?);
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqual(2, cache.count());
}

test "overwrite refreshes recency" {
    var cache = try LruCache.init(testing.allocator, 2);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try cache.put(testing.allocator, "a", "9");
    try cache.put(testing.allocator, "c", "3");
    try testing.expectEqualStrings("9", cache.get("a").?);
    try testing.expectEqual(null, cache.get("b"));
    try testing.expectEqualStrings("3", cache.get("c").?);
}

test "remove and slot reuse" {
    var cache = try LruCache.init(testing.allocator, 3);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "x", "1");
    try testing.expect(cache.remove("x"));
    try testing.expect(!cache.remove("x"));
    try testing.expectEqual(0, cache.count());
    try testing.expectEqual(null, cache.get("x"));

    try cache.put(testing.allocator, "y", "2");
    try testing.expectEqual(2, cache.slots.items.len);
    try testing.expectEqualStrings("2", cache.get("y").?);
}

test "capacity one" {
    var cache = try LruCache.init(testing.allocator, 1);
    defer cache.deinit(testing.allocator);

    try cache.put(testing.allocator, "a", "1");
    try cache.put(testing.allocator, "b", "2");
    try testing.expectEqual(null, cache.get("a"));
    try testing.expectEqualStrings("2", cache.get("b").?);
    try testing.expectEqual(1, cache.count());
}

test "rejects oversized entries" {
    var cache = try LruCache.init(testing.allocator, 1);
    defer cache.deinit(testing.allocator);

    const long = "k" ** (max_len + 1);
    try testing.expectError(error.KeyTooLong, cache.put(testing.allocator, long, "v"));
    try testing.expectError(error.ValueTooLong, cache.put(testing.allocator, "k", long));
    try testing.expectEqual(null, cache.get(long));
    try cache.put(testing.allocator, "k" ** max_len, "v" ** max_len);
    try testing.expectEqualStrings("v" ** max_len, cache.get("k" ** max_len).?);
}

test "matches a reference model under random operations" {
    const gpa = testing.allocator;
    var cache = try LruCache.init(gpa, 8);
    defer cache.deinit(gpa);

    // Reference: keys ordered from least to most recently used.
    var model: std.ArrayList(struct { key: u8, value: u32 }) = .empty;
    defer model.deinit(gpa);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    for (0..20_000) |_| {
        const k = random.uintLessThan(u8, 20);
        const key: []const u8 = &.{ 'a' + k };
        const pos = for (model.items, 0..) |e, i| {
            if (e.key == k) break i;
        } else null;
        switch (random.uintLessThan(u8, 3)) {
            0 => {
                const v = random.int(u32);
                var buf: [16]u8 = undefined;
                try cache.put(gpa, key, try std.fmt.bufPrint(&buf, "{d}", .{v}));
                if (pos) |i| _ = model.orderedRemove(i);
                try model.append(gpa, .{ .key = k, .value = v });
                if (model.items.len > 8) _ = model.orderedRemove(0);
            },
            1 => {
                const got = cache.get(key);
                if (pos) |i| {
                    const e = model.orderedRemove(i);
                    var buf: [16]u8 = undefined;
                    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{d}", .{e.value}), got.?);
                    try model.append(gpa, e);
                } else try testing.expectEqual(null, got);
            },
            else => {
                try testing.expectEqual(pos != null, cache.remove(key));
                if (pos) |i| _ = model.orderedRemove(i);
            },
        }
        try testing.expectEqual(model.items.len, cache.count());
    }
}
