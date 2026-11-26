//! lru — simulate an LRU cache driven by commands on standard input.
//!
//! The whole input is read into memory once; keys and values are stored as
//! slices into that buffer, so no per-entry allocation is needed. Entries live
//! in a preallocated node pool linked into an intrusive doubly linked recency
//! list and a chained hash table, giving O(1) expected time per command.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const max_capacity = 1_000_000;

/// Longest key or value accepted; longer tokens make the command a no-op.
const max_token_len = std.math.maxInt(u8);

pub const Cache = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        hash: u32,
        /// Towards more recently used.
        prev: Index,
        /// Towards less recently used.
        next: Index,
        /// Next node in the same hash bucket, or in the free list.
        chain: Index,
    };

    nodes: []Node,
    buckets: []Index,
    capacity: u32,
    size: u32 = 0,
    /// Nodes ever handed out from the pool.
    used: u32 = 0,
    /// Head of the list of recycled nodes.
    free_head: Index = none,
    /// Most recently used.
    head: Index = none,
    /// Least recently used.
    tail: Index = none,

    /// `max_nodes` bounds how many entries can ever be live at once; it must
    /// be at least 1 and at most `capacity`.
    pub fn init(gpa: Allocator, capacity: u32, max_nodes: u32) Allocator.Error!Cache {
        std.debug.assert(max_nodes >= 1 and max_nodes <= capacity);
        const bucket_count = std.math.ceilPowerOfTwoAssert(usize, @max(16, @as(usize, max_nodes) * 2));

        const nodes = try gpa.alloc(Node, max_nodes);
        errdefer gpa.free(nodes);
        const buckets = try gpa.alloc(Index, bucket_count);
        @memset(buckets, none);

        return .{ .nodes = nodes, .buckets = buckets, .capacity = capacity };
    }

    pub fn deinit(c: *Cache, gpa: Allocator) void {
        gpa.free(c.nodes);
        gpa.free(c.buckets);
        c.* = undefined;
    }

    fn hashKey(key: []const u8) u32 {
        return @truncate(std.hash.Wyhash.hash(0, key));
    }

    fn bucketFor(c: *Cache, hash: u32) *Index {
        return &c.buckets[hash & (c.buckets.len - 1)];
    }

    /// Returns the hash-chain link that points at the node holding `key`,
    /// or null if the key is absent.
    fn findSlot(c: *Cache, key: []const u8, hash: u32) ?*Index {
        var slot = c.bucketFor(hash);
        while (slot.* != none) {
            const n = &c.nodes[slot.*];
            if (n.hash == hash and std.mem.eql(u8, n.key, key)) return slot;
            slot = &n.chain;
        }
        return null;
    }

    fn unlink(c: *Cache, i: Index) void {
        const n = &c.nodes[i];
        if (n.prev != none) c.nodes[n.prev].next = n.next else c.head = n.next;
        if (n.next != none) c.nodes[n.next].prev = n.prev else c.tail = n.prev;
    }

    fn pushFront(c: *Cache, i: Index) void {
        const n = &c.nodes[i];
        n.prev = none;
        n.next = c.head;
        if (c.head != none) c.nodes[c.head].prev = i else c.tail = i;
        c.head = i;
    }

    fn touch(c: *Cache, i: Index) void {
        if (c.head == i) return;
        c.unlink(i);
        c.pushFront(i);
    }

    /// Removes the node that `slot` points at and recycles it.
    fn removeAt(c: *Cache, slot: *Index) void {
        const i = slot.*;
        slot.* = c.nodes[i].chain;
        c.unlink(i);
        c.nodes[i].chain = c.free_head;
        c.free_head = i;
        c.size -= 1;
    }

    fn allocNode(c: *Cache) Index {
        if (c.free_head != none) {
            const i = c.free_head;
            c.free_head = c.nodes[i].chain;
            return i;
        }
        const i = c.used;
        c.used += 1;
        return i;
    }

    /// Looks up `key`, marking it most recently used on a hit.
    pub fn get(c: *Cache, key: []const u8) ?[]const u8 {
        const slot = c.findSlot(key, hashKey(key)) orelse return null;
        const i = slot.*;
        c.touch(i);
        return c.nodes[i].value;
    }

    /// Removes `key`; returns whether it was present.
    pub fn del(c: *Cache, key: []const u8) bool {
        const slot = c.findSlot(key, hashKey(key)) orelse return false;
        c.removeAt(slot);
        return true;
    }

    /// Inserts or overwrites `key`, evicting the least recently used entry
    /// if the cache is full. The slices must outlive the cache.
    pub fn set(c: *Cache, key: []const u8, value: []const u8) void {
        const hash = hashKey(key);
        if (c.findSlot(key, hash)) |slot| {
            const i = slot.*;
            c.nodes[i].value = value;
            c.touch(i);
            return;
        }

        if (c.size == c.capacity) {
            const lru = &c.nodes[c.tail];
            c.removeAt(c.findSlot(lru.key, lru.hash).?);
        }

        const i = c.allocNode();
        const bucket = c.bucketFor(hash);
        c.nodes[i] = .{
            .key = key,
            .value = value,
            .hash = hash,
            .prev = none,
            .next = none,
            .chain = bucket.*,
        };
        bucket.* = i;
        c.pushFront(i);
        c.size += 1;
    }
};

/// Parses the capacity line the way C's `strtol` would (leading whitespace,
/// optional sign, decimal digits, saturating), then clamps to the valid range.
/// Like the original, only the first 31 bytes of the line are considered.
pub fn parseCapacity(line: []const u8) u32 {
    const s = line[0..@min(line.len, 31)];
    var i: usize = 0;
    while (i < s.len and std.ascii.isWhitespace(s[i])) i += 1;
    var negative = false;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        negative = s[i] == '-';
        i += 1;
    }
    var value: u64 = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {
        value = @min(value * 10 + (s[i] - '0'), max_capacity + 1);
    }
    if (negative or value < 1) return 1;
    return @intCast(@min(value, max_capacity));
}

fn runCommand(c: *Cache, out: *Io.Writer, line: []const u8) Io.Writer.Error!void {
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const cmd = tokens.next() orelse return;

    if (std.mem.eql(u8, cmd, "SIZE")) {
        try out.print("{d}\n", .{c.size});
        return;
    }
    if (cmd.len != 3) return;
    const key = tokens.next() orelse return;
    if (key.len > max_token_len) return;

    if (std.mem.eql(u8, cmd, "GET")) {
        try out.writeAll(c.get(key) orelse "NULL");
        try out.writeByte('\n');
    } else if (std.mem.eql(u8, cmd, "DEL")) {
        try out.writeAll(if (c.del(key)) "1\n" else "0\n");
    } else if (std.mem.eql(u8, cmd, "SET")) {
        const value = tokens.next() orelse return;
        if (value.len > max_token_len) return;
        c.set(key, value);
    }
}

fn trimCr(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\r")) line[0 .. line.len - 1] else line;
}

/// Executes the whole program on `input`, writing results to `out`.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    if (input.len == 0) return;

    var lines = std.mem.splitScalar(u8, input, '\n');
    const capacity = parseCapacity(trimCr(lines.first()));

    // The pool never needs more nodes than the capacity or the number of
    // remaining lines, whichever is smaller.
    const rest = lines.rest();
    const line_count = std.mem.countScalar(u8, rest, '\n') + 1;
    const max_nodes: u32 = @intCast(@min(capacity, line_count));

    var cache: Cache = try .init(gpa, capacity, max_nodes);
    defer cache.deinit(gpa);

    while (lines.next()) |line| {
        try runCommand(&cache, out, trimCr(line));
    }
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
    run(gpa, input, &stdout.interface) catch |err| switch (err) {
        error.WriteFailed => return stdout.err.?,
        else => |e| return e,
    };
    stdout.interface.flush() catch return stdout.err.?;
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
    try expectRun("3\r\nSET x 1\r\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "empty input" {
    try expectRun("", "");
}

test "parseCapacity" {
    try std.testing.expectEqual(@as(u32, 5), parseCapacity("  +5x"));
    try std.testing.expectEqual(@as(u32, 1), parseCapacity("-3"));
    try std.testing.expectEqual(@as(u32, 1), parseCapacity("abc"));
    try std.testing.expectEqual(@as(u32, max_capacity), parseCapacity("99999999999999999999999"));
}
