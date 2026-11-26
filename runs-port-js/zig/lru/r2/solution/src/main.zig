//! LRU cache simulator.
//!
//! Reads a capacity on the first line of stdin, then one command per line
//! (`SET k v`, `GET k`, `DEL k`, `SIZE`), and writes one output line for
//! every command that produces output. See SPEC.md.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Fixed-capacity LRU cache backed by a hash index and an intrusive doubly
/// linked list stored in parallel arrays. Every operation is O(1) expected.
///
/// Slot 0 is the list sentinel: `next[0]` is the most recently used entry and
/// `prev[0]` the least recently used. Keys and values are borrowed slices; the
/// caller must keep them alive for as long as they are in the cache.
pub const LruCache = struct {
    pub const Slot = u32;
    const sentinel: Slot = 0;

    index: Index,
    keys: [][]const u8,
    values: [][]const u8,
    prev: []Slot,
    next: []Slot,
    free: []Slot,
    free_count: usize,

    pub fn init(gpa: Allocator, capacity: Slot) Allocator.Error!LruCache {
        std.debug.assert(capacity >= 1);
        const slots = @as(usize, capacity) + 1;

        var index = try Index.init(gpa, capacity);
        errdefer index.deinit(gpa);
        const keys = try gpa.alloc([]const u8, slots);
        errdefer gpa.free(keys);
        const values = try gpa.alloc([]const u8, slots);
        errdefer gpa.free(values);
        const prev = try gpa.alloc(Slot, slots);
        errdefer gpa.free(prev);
        const next = try gpa.alloc(Slot, slots);
        errdefer gpa.free(next);
        const free = try gpa.alloc(Slot, capacity);
        errdefer gpa.free(free);

        // Hand out low slots first: free[free_count - 1] is popped next.
        for (free, 0..) |*f, i| f.* = capacity - @as(Slot, @intCast(i));
        prev[sentinel] = sentinel;
        next[sentinel] = sentinel;

        return .{
            .index = index,
            .keys = keys,
            .values = values,
            .prev = prev,
            .next = next,
            .free = free,
            .free_count = capacity,
        };
    }

    pub fn deinit(self: *LruCache, gpa: Allocator) void {
        self.index.deinit(gpa);
        gpa.free(self.keys);
        gpa.free(self.values);
        gpa.free(self.prev);
        gpa.free(self.next);
        gpa.free(self.free);
        self.* = undefined;
    }

    pub fn count(self: *const LruCache) usize {
        return self.free.len - self.free_count;
    }

    /// Returns the value for `key` and marks it most recently used, or null.
    pub fn get(self: *LruCache, key: []const u8) ?[]const u8 {
        const found = self.index.find(self.keys, key, Index.hash(key)) orelse return null;
        const slot = self.index.buckets[found].slot;
        self.touch(slot);
        return self.values[slot];
    }

    /// Inserts or overwrites `key`, making it most recently used. Evicts the
    /// least recently used entry if the cache would exceed its capacity.
    pub fn put(self: *LruCache, key: []const u8, value: []const u8) void {
        const h = Index.hash(key);
        if (self.index.find(self.keys, key, h)) |found| {
            const slot = self.index.buckets[found].slot;
            self.values[slot] = value;
            self.touch(slot);
            return;
        }
        if (self.free_count == 0) self.evict(self.prev[sentinel]);
        self.free_count -= 1;
        const slot = self.free[self.free_count];
        self.keys[slot] = key;
        self.values[slot] = value;
        self.index.insert(h, slot);
        self.pushFront(slot);
    }

    /// Removes `key`. Returns whether it was present.
    pub fn remove(self: *LruCache, key: []const u8) bool {
        const found = self.index.find(self.keys, key, Index.hash(key)) orelse return false;
        const slot = self.index.buckets[found].slot;
        self.index.removeAt(found);
        self.release(slot);
        return true;
    }

    fn evict(self: *LruCache, slot: Slot) void {
        const key = self.keys[slot];
        const found = self.index.find(self.keys, key, Index.hash(key)).?;
        self.index.removeAt(found);
        self.release(slot);
    }

    fn release(self: *LruCache, slot: Slot) void {
        std.debug.assert(slot != sentinel);
        self.unlink(slot);
        self.free[self.free_count] = slot;
        self.free_count += 1;
    }

    fn touch(self: *LruCache, slot: Slot) void {
        if (self.next[sentinel] == slot) return;
        self.unlink(slot);
        self.pushFront(slot);
    }

    fn unlink(self: *LruCache, slot: Slot) void {
        const p = self.prev[slot];
        const n = self.next[slot];
        self.next[p] = n;
        self.prev[n] = p;
    }

    fn pushFront(self: *LruCache, slot: Slot) void {
        const first = self.next[sentinel];
        self.prev[slot] = sentinel;
        self.next[slot] = first;
        self.prev[first] = slot;
        self.next[sentinel] = slot;
    }

    /// Open-addressing hash index from key to slot, using linear probing with
    /// backward-shift deletion. Sized once for the cache capacity at a load
    /// factor of at most 1/2, so it never grows and never accumulates
    /// tombstones, which keeps lookups O(1) expected under heavy churn.
    const Index = struct {
        const Bucket = struct {
            /// `sentinel` marks an empty bucket.
            slot: Slot,
            /// Low bits of the key hash; avoids most key comparisons.
            hash: u32,
        };

        buckets: []Bucket,
        mask: u32,

        fn init(gpa: Allocator, capacity: Slot) Allocator.Error!Index {
            const len = std.math.ceilPowerOfTwoAssert(usize, @max(2 * @as(usize, capacity), 8));
            const buckets = try gpa.alloc(Bucket, len);
            @memset(buckets, .{ .slot = sentinel, .hash = 0 });
            return .{ .buckets = buckets, .mask = @intCast(len - 1) };
        }

        fn deinit(self: *Index, gpa: Allocator) void {
            gpa.free(self.buckets);
            self.* = undefined;
        }

        fn hash(key: []const u8) u32 {
            return @truncate(std.hash.Wyhash.hash(0, key));
        }

        /// Returns the bucket position holding `key`, or null if absent.
        fn find(self: *const Index, keys: []const []const u8, key: []const u8, h: u32) ?u32 {
            var i = h & self.mask;
            while (true) : (i = (i + 1) & self.mask) {
                const b = self.buckets[i];
                if (b.slot == sentinel) return null;
                if (b.hash == h and std.mem.eql(u8, keys[b.slot], key)) return i;
            }
        }

        /// Inserts a key known to be absent.
        fn insert(self: *Index, h: u32, slot: Slot) void {
            var i = h & self.mask;
            while (self.buckets[i].slot != sentinel) i = (i + 1) & self.mask;
            self.buckets[i] = .{ .slot = slot, .hash = h };
        }

        /// Empties bucket `hole`, shifting later members of its probe run
        /// back so every remaining key stays reachable from its home bucket.
        fn removeAt(self: *Index, hole_start: u32) void {
            var hole = hole_start;
            var i = hole;
            while (true) {
                i = (i + 1) & self.mask;
                const b = self.buckets[i];
                if (b.slot == sentinel) break;
                const home = b.hash & self.mask;
                // Move `b` into the hole unless its home lies in (hole, i].
                if (((i -% home) & self.mask) >= ((i -% hole) & self.mask)) {
                    self.buckets[hole] = b;
                    hole = i;
                }
            }
            self.buckets[hole] = .{ .slot = sentinel, .hash = 0 };
        }
    };
};

pub const max_capacity = 1_000_000;

pub const RunError = error{InvalidCapacity} || Allocator.Error || Io.Writer.Error;

/// Parses the capacity line: optional surrounding whitespace around a
/// decimal integer in `1..max_capacity`.
fn parseCapacity(line: []const u8) error{InvalidCapacity}!u32 {
    const text = std.mem.trim(u8, line, " \t\r");
    const value = std.fmt.parseUnsigned(u32, text, 10) catch return error.InvalidCapacity;
    if (value < 1 or value > max_capacity) return error.InvalidCapacity;
    return value;
}

/// Runs the simulation over `input`, writing results to `out`. Keys and
/// values are borrowed from `input`, which must outlive this call.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) RunError!void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = try parseCapacity(lines.first());

    var cache = try LruCache.init(gpa, capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;

        var tokens = std.mem.splitScalar(u8, line, ' ');
        const cmd = tokens.first();
        const rest = tokens.rest();

        if (std.mem.eql(u8, cmd, "SET")) {
            const sp = std.mem.indexOfScalar(u8, rest, ' ') orelse continue;
            cache.put(rest[0..sp], rest[sp + 1 ..]);
        } else if (std.mem.eql(u8, cmd, "GET")) {
            try out.writeAll(cache.get(rest) orelse "NULL");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, cmd, "DEL")) {
            try out.writeAll(if (cache.remove(rest)) "1\n" else "0\n");
        } else if (std.mem.eql(u8, cmd, "SIZE")) {
            try out.print("{d}\n", .{cache.count()});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &stdout.interface;

    run(gpa, input, out) catch |err| switch (err) {
        error.InvalidCapacity => {
            std.log.err("first line must be a capacity between 1 and {d}", .{max_capacity});
            std.process.exit(1);
        },
        else => |e| return e,
    };
    try out.flush();
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
    try expectRun("2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n", "9\nNULL\n3\n");
}

test "delete and size" {
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x", "1\n0\n0\nNULL\n");
}

test "capacity one, CRLF, blank lines" {
    try expectRun("1\r\nSET a 1\r\n\r\nSET b 2\r\nGET a\r\nGET b\r\nSIZE\r\n", "NULL\n2\n1\n");
}

test "slots are reused after eviction and deletion" {
    try expectRun("2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n");
}

test "invalid capacity" {
    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try std.testing.expectError(error.InvalidCapacity, run(std.testing.allocator, "0\n", &out.writer));
    try std.testing.expectError(error.InvalidCapacity, run(std.testing.allocator, "abc\n", &out.writer));
}

test "index stays consistent under churn" {
    const gpa = std.testing.allocator;
    var cache = try LruCache.init(gpa, 64);
    defer cache.deinit(gpa);

    var names: [512][8]u8 = undefined;
    for (&names, 0..) |*n, i| _ = std.fmt.bufPrint(n, "k{d:0>7}", .{i}) catch unreachable;

    var prng: std.Random.DefaultPrng = .init(42);
    const random = prng.random();
    for (0..20_000) |_| {
        const key: []const u8 = &names[random.uintLessThan(usize, names.len)];
        switch (random.uintLessThan(u8, 3)) {
            0 => cache.put(key, key),
            1 => if (cache.get(key)) |v| try std.testing.expectEqualStrings(key, v),
            else => _ = cache.remove(key),
        }
        try std.testing.expect(cache.count() <= 64);
    }
    // Every key still linked in the list must be findable through the index.
    var slot = cache.next[0];
    var n: usize = 0;
    while (slot != 0) : (slot = cache.next[slot]) {
        const key = cache.keys[slot];
        const found = cache.index.find(cache.keys, key, LruCache.Index.hash(key)).?;
        try std.testing.expectEqual(slot, cache.index.buckets[found].slot);
        n += 1;
    }
    try std.testing.expectEqual(cache.count(), n);
}
