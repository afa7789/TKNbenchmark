//! `lru`: simulate a least-recently-used cache driven by text commands.
//!
//! Keys and values borrow from the input buffer, so the cache never copies
//! strings. Entries live in a slot array linked into a recency list by index;
//! a hash map from key to slot gives O(1) expected time per command.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Index = u32;
const none = std.math.maxInt(Index);

const Slot = struct {
    key: []const u8,
    value: []const u8,
    prev: Index,
    next: Index,
};

pub const Cache = struct {
    capacity: usize,
    slots: std.ArrayList(Slot) = .empty,
    map: std.StringHashMapUnmanaged(Index) = .empty,
    /// Most recently used slot.
    head: Index = none,
    /// Least recently used slot.
    tail: Index = none,
    /// Slots released by `del`, chained through `next`.
    free: Index = none,
    /// Map removals since the last rehash; each one leaves a tombstone.
    tombstones: usize = 0,

    pub fn init(capacity: usize) Cache {
        std.debug.assert(capacity >= 1);
        return .{ .capacity = capacity };
    }

    pub fn deinit(c: *Cache, gpa: Allocator) void {
        c.slots.deinit(gpa);
        c.map.deinit(gpa);
        c.* = undefined;
    }

    pub fn size(c: *const Cache) usize {
        return c.map.count();
    }

    pub fn get(c: *Cache, key: []const u8) ?[]const u8 {
        const index = c.map.get(key) orelse return null;
        c.moveToFront(index);
        return c.slots.items[index].value;
    }

    pub fn set(c: *Cache, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try c.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            const index = gop.value_ptr.*;
            c.slots.items[index].value = value;
            c.moveToFront(index);
            return;
        }

        const index: Index = if (c.map.count() > c.capacity) blk: {
            // Over capacity: recycle the least recently used slot for the new key.
            const victim = c.tail;
            c.unlink(victim);
            const removed = c.map.remove(c.slots.items[victim].key);
            std.debug.assert(removed);
            c.noteRemoval();
            break :blk victim;
        } else if (c.free != none) blk: {
            const reused = c.free;
            c.free = c.slots.items[reused].next;
            break :blk reused;
        } else blk: {
            const fresh: Index = @intCast(c.slots.items.len);
            c.slots.append(gpa, undefined) catch |err| {
                c.map.removeByPtr(gop.key_ptr);
                return err;
            };
            break :blk fresh;
        };

        // Removal only leaves a tombstone, so `gop` still points at the new entry.
        gop.value_ptr.* = index;
        c.slots.items[index] = .{ .key = key, .value = value, .prev = none, .next = none };
        c.pushFront(index);
    }

    /// Removes `key`; returns whether it was present.
    pub fn del(c: *Cache, key: []const u8) bool {
        const kv = c.map.fetchRemove(key) orelse return false;
        c.noteRemoval();
        c.unlink(kv.value);
        c.slots.items[kv.value].next = c.free;
        c.free = kv.value;
        return true;
    }

    /// Reserves map space for `count` keys with enough headroom that tombstones
    /// are purged by `noteRemoval` before they could force the map to grow.
    pub fn reserve(c: *Cache, gpa: Allocator, count: usize) Allocator.Error!void {
        try c.map.ensureTotalCapacity(gpa, @intCast(2 * count));
        try c.slots.ensureTotalCapacity(gpa, count);
    }

    /// Tombstones lengthen probe sequences and are only cleared by a rehash;
    /// rehashing after every capacity/8 removals keeps the cost amortized O(1).
    fn noteRemoval(c: *Cache) void {
        c.tombstones += 1;
        if (c.tombstones >= c.map.capacity() / 8) {
            c.map.rehash(std.hash_map.StringContext{});
            c.tombstones = 0;
        }
    }

    fn moveToFront(c: *Cache, index: Index) void {
        if (c.head == index) return;
        c.unlink(index);
        c.pushFront(index);
    }

    fn pushFront(c: *Cache, index: Index) void {
        const slot = &c.slots.items[index];
        slot.prev = none;
        slot.next = c.head;
        if (c.head != none) c.slots.items[c.head].prev = index else c.tail = index;
        c.head = index;
    }

    fn unlink(c: *Cache, index: Index) void {
        const slot = c.slots.items[index];
        if (slot.prev != none) c.slots.items[slot.prev].next = slot.next else c.head = slot.next;
        if (slot.next != none) c.slots.items[slot.next].prev = slot.prev else c.tail = slot.prev;
    }
};

pub const max_capacity = 1_000_000;

/// Runs the command script in `input` and writes command results to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const first = trimCr(lines.first());
    const parsed = std.fmt.parseUnsigned(usize, std.mem.trim(u8, first, " \t"), 10) catch return;
    const capacity = std.math.clamp(parsed, 1, max_capacity);

    var cache: Cache = .init(capacity);
    defer cache.deinit(gpa);

    // Reserve up front: the map never holds more than capacity + 1 keys, and
    // there cannot be more keys than lines of input.
    const expected: usize = @min(capacity + 1, std.mem.count(u8, input, "\n") + 1);
    try cache.reserve(gpa, expected);

    while (lines.next()) |raw| {
        const line = trimCr(raw);
        var tokens = std.mem.splitScalar(u8, line, ' ');
        const op = tokens.first();
        if (std.mem.eql(u8, op, "SET")) {
            const key = tokens.next() orelse continue;
            const value = tokens.next() orelse continue;
            try cache.set(gpa, key, value);
        } else if (std.mem.eql(u8, op, "GET")) {
            const key = tokens.next() orelse continue;
            try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
        } else if (std.mem.eql(u8, op, "DEL")) {
            const key = tokens.next() orelse continue;
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, op, "SIZE")) {
            try out.print("{d}\n", .{cache.size()});
        }
    }
}

fn trimCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

fn expectOutput(input: []const u8, expected: []const u8) !void {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectOutput("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectOutput("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete, reuse and capacity one" {
    try expectOutput("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\nSET y 2\nSET z 3\nSIZE\n", "1\n0\n0\nNULL\n2\n");
    try expectOutput("1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE\n", "NULL\n2\n1\n");
}
