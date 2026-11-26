//! lru — simulate an LRU cache driven by commands on standard input.
//!
//! The whole input is read into memory once; keys and values are stored as
//! slices of that buffer, so no per-entry allocation is needed. Entries live
//! in a fixed pool linked into a doubly linked recency list and indexed by an
//! open-addressing hash table (linear probing, backward-shift deletion).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Cache = struct {
    const Index = u32;
    const nil: Index = std.math.maxInt(Index);
    /// Slot value meaning "empty"; occupied slots hold an entry index.
    const empty_slot: Index = nil;

    const Entry = struct {
        key: []const u8,
        value: []const u8,
        hash: u32,
        /// Towards the most recently used entry.
        prev: Index,
        /// Towards the least recently used entry (also links the free list).
        next: Index,
    };

    /// Pool of `capacity` entries.
    entries: []Entry,
    /// Open-addressing table of entry indices; `empty_slot` marks a hole.
    slots: []Index,
    /// Slot count - 1 (slot count is a power of two).
    mask: u32,
    /// Maximum number of keys held.
    capacity: u32,
    /// Number of keys held.
    size: u32 = 0,
    /// Most recently used entry, or `nil`.
    head: Index = nil,
    /// Least recently used entry, or `nil`.
    tail: Index = nil,
    /// Top of the free-entry stack (linked via `next`), or `nil`.
    free_top: Index = nil,
    /// First never-used pool index.
    unused: Index = 0,

    pub fn init(gpa: Allocator, capacity: u32) Allocator.Error!Cache {
        std.debug.assert(capacity >= 1 and capacity < nil);
        // Keep the load factor at or below one half.
        const slot_count = std.math.ceilPowerOfTwoAssert(u64, @max(16, @as(u64, capacity) * 2));

        const entries = try gpa.alloc(Entry, capacity);
        errdefer gpa.free(entries);
        const slots = try gpa.alloc(Index, @intCast(slot_count));
        @memset(slots, empty_slot);

        return .{
            .entries = entries,
            .slots = slots,
            .mask = @intCast(slot_count - 1),
            .capacity = capacity,
        };
    }

    pub fn deinit(c: *Cache, gpa: Allocator) void {
        gpa.free(c.entries);
        gpa.free(c.slots);
        c.* = undefined;
    }

    /// Inserts or overwrites `key`, making it the most recently used and
    /// evicting the least recently used key if capacity would be exceeded.
    pub fn set(c: *Cache, key: []const u8, value: []const u8) void {
        const hash = hashKey(key);
        var slot = c.findSlot(key, hash);

        if (c.slots[slot] != empty_slot) {
            const idx = c.slots[slot];
            c.entries[idx].value = value;
            c.touch(idx);
            return;
        }

        if (c.size == c.capacity) {
            const lru = &c.entries[c.tail];
            c.removeAt(c.findSlot(lru.key, lru.hash));
            // Backward-shift deletion may have moved the target slot.
            slot = c.findSlot(key, hash);
        }

        const idx = c.allocEntry();
        c.entries[idx] = .{
            .key = key,
            .value = value,
            .hash = hash,
            .prev = nil,
            .next = nil,
        };
        c.slots[slot] = idx;
        c.pushFront(idx);
        c.size += 1;
    }

    /// Looks up `key`; a hit makes it the most recently used.
    pub fn get(c: *Cache, key: []const u8) ?[]const u8 {
        const idx = c.slots[c.findSlot(key, hashKey(key))];
        if (idx == empty_slot) return null;
        c.touch(idx);
        return c.entries[idx].value;
    }

    /// Removes `key`, returning whether it was present.
    pub fn del(c: *Cache, key: []const u8) bool {
        const slot = c.findSlot(key, hashKey(key));
        if (c.slots[slot] == empty_slot) return false;
        c.removeAt(slot);
        return true;
    }

    fn hashKey(key: []const u8) u32 {
        return @truncate(std.hash.Wyhash.hash(0, key));
    }

    /// Returns the slot holding `key`, or the empty slot where it would go.
    fn findSlot(c: *const Cache, key: []const u8, hash: u32) u32 {
        var i = hash & c.mask;
        while (true) : (i = (i + 1) & c.mask) {
            const idx = c.slots[i];
            if (idx == empty_slot) return i;
            const e = &c.entries[idx];
            if (e.hash == hash and std.mem.eql(u8, e.key, key)) return i;
        }
    }

    /// Empties slot `hole`, shifting later cluster members back so that every
    /// remaining key stays reachable from its home slot.
    fn removeSlot(c: *Cache, hole: u32) void {
        var i = hole;
        var j = hole;
        while (true) {
            j = (j + 1) & c.mask;
            const idx = c.slots[j];
            if (idx == empty_slot) break;
            const home = c.entries[idx].hash & c.mask;
            // The entry may stay only if its home lies cyclically in (i, j].
            const stays = if (i <= j)
                i < home and home <= j
            else
                i < home or home <= j;
            if (!stays) {
                c.slots[i] = idx;
                i = j;
            }
        }
        c.slots[i] = empty_slot;
    }

    fn unlink(c: *Cache, idx: Index) void {
        const e = &c.entries[idx];
        if (e.prev != nil) c.entries[e.prev].next = e.next else c.head = e.next;
        if (e.next != nil) c.entries[e.next].prev = e.prev else c.tail = e.prev;
    }

    fn pushFront(c: *Cache, idx: Index) void {
        const e = &c.entries[idx];
        e.prev = nil;
        e.next = c.head;
        if (c.head != nil) c.entries[c.head].prev = idx else c.tail = idx;
        c.head = idx;
    }

    fn touch(c: *Cache, idx: Index) void {
        if (c.head == idx) return;
        c.unlink(idx);
        c.pushFront(idx);
    }

    /// Removes the entry in `slot` from the cache and recycles it.
    fn removeAt(c: *Cache, slot: u32) void {
        const idx = c.slots[slot];
        c.removeSlot(slot);
        c.unlink(idx);
        c.entries[idx].next = c.free_top;
        c.free_top = idx;
        c.size -= 1;
    }

    fn allocEntry(c: *Cache) Index {
        if (c.free_top != nil) {
            const idx = c.free_top;
            c.free_top = c.entries[idx].next;
            return idx;
        }
        std.debug.assert(c.unused < c.capacity);
        defer c.unused += 1;
        return c.unused;
    }
};

const max_capacity = 1_000_000;

/// Parses the capacity line leniently: leading blanks are skipped, parsing
/// stops at the first non-digit, and the result is clamped to [1, max].
fn parseCapacity(line: []const u8) u32 {
    const digits = std.mem.trimStart(u8, line, " \t");
    var v: u32 = 0;
    for (digits) |ch| {
        if (!std.ascii.isDigit(ch)) break;
        v = @min(max_capacity, v *| 10 +| (ch - '0'));
    }
    return @max(1, v);
}

/// Executes every command in `input` against a fresh cache, writing results to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(lines.first());

    var cache: Cache = try .init(gpa, capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const cmd = tokens.next() orelse continue;
        const key = tokens.next() orelse "";

        if (std.mem.eql(u8, cmd, "SET")) {
            if (key.len > 0) cache.set(key, tokens.next() orelse "");
        } else if (std.mem.eql(u8, cmd, "GET")) {
            try out.print("{s}\n", .{cache.get(key) orelse "NULL"});
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            try out.writeAll(if (cache.del(key)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.size});
        }
    }
    try out.flush();
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    try run(gpa, input, &stdout.interface);
}

fn expectRun(input: []const u8, expected: []const u8) !void {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try run(std.testing.allocator, input, &out.writer);
    try std.testing.expectEqualStrings(expected, out.written());
}

test "spec example" {
    try expectRun("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n", "1\nNULL\n2\n");
}

test "overwrite refreshes recency" {
    try expectRun("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one and CRLF" {
    try expectRun("1\r\nSET a 1\r\nSET b 2\r\nGET a\r\nGET b\r\nSIZE\r\n", "NULL\n2\n1\n");
}

test "parseCapacity clamps" {
    try std.testing.expectEqual(@as(u32, 1), parseCapacity("0"));
    try std.testing.expectEqual(@as(u32, 42), parseCapacity("  42x"));
    try std.testing.expectEqual(@as(u32, max_capacity), parseCapacity("99999999999999999999"));
}

test "matches a reference model under churn" {
    const gpa = std.testing.allocator;
    var cache: Cache = try .init(gpa, 8);
    defer cache.deinit(gpa);

    // Reference: recency-ordered list of keys (front = most recent).
    var model: std.ArrayList(u8) = .empty;
    defer model.deinit(gpa);

    const keys = "abcdefghijklmnopqrstuvwxyz";
    var prng: std.Random.DefaultPrng = .init(1);
    const rand = prng.random();
    for (0..20_000) |_| {
        const k = rand.uintLessThan(usize, keys.len);
        const key = keys[k..][0..1];
        const pos = std.mem.indexOfScalar(u8, model.items, keys[k]);
        switch (rand.uintLessThan(u8, 3)) {
            0 => {
                cache.set(key, key);
                if (pos) |p| _ = model.orderedRemove(p);
                try model.insert(gpa, 0, keys[k]);
                if (model.items.len > 8) _ = model.pop();
            },
            1 => {
                const got = cache.get(key);
                try std.testing.expectEqual(pos != null, got != null);
                if (pos) |p| {
                    _ = model.orderedRemove(p);
                    try model.insert(gpa, 0, keys[k]);
                }
            },
            else => {
                try std.testing.expectEqual(pos != null, cache.del(key));
                if (pos) |p| _ = model.orderedRemove(p);
            },
        }
        try std.testing.expectEqual(model.items.len, cache.size);
    }
}
