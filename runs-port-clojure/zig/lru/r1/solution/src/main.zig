//! LRU cache simulator.
//!
//! Reads a capacity followed by a stream of commands from standard input and
//! writes command results to standard output. See SPEC.md for the protocol.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// A fixed-capacity least-recently-used cache mapping byte strings to byte
/// strings. Keys and values are borrowed: the caller must keep them alive for
/// as long as they are stored in the cache.
pub const Lru = struct {
    const Index = u32;
    const none: Index = std.math.maxInt(Index);

    const Node = struct {
        key: []const u8,
        value: []const u8,
        prev: Index,
        next: Index,
    };

    capacity: usize,
    map: std.StringHashMapUnmanaged(Index) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    /// Head of a singly linked list (through `next`) of recycled nodes.
    free: Index = none,
    /// Most recently used node.
    head: Index = none,
    /// Least recently used node.
    tail: Index = none,
    /// Removals since the map was last rehashed; see `noteRemoval`.
    removals: usize = 0,

    pub fn init(gpa: Allocator, capacity: usize) Allocator.Error!Lru {
        var self: Lru = .{ .capacity = capacity };
        errdefer self.deinit(gpa);
        // Never more than capacity + 1 live entries; cap the up-front
        // reservation so an absurd capacity does not exhaust memory. The map
        // gets twice that so its load factor stays low under churn.
        const live: u32 = @intCast(@min(capacity + 1, 1 << 20));
        try self.map.ensureTotalCapacity(gpa, 2 * live);
        try self.nodes.ensureTotalCapacity(gpa, live);
        return self;
    }

    pub fn deinit(self: *Lru, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.nodes.deinit(gpa);
        self.* = undefined;
    }

    pub fn count(self: *const Lru) usize {
        return self.map.count();
    }

    /// Returns the value for `key`, marking it as most recently used.
    pub fn get(self: *Lru, key: []const u8) ?[]const u8 {
        const idx = self.map.get(key) orelse return null;
        self.moveToFront(idx);
        return self.nodes.items[idx].value;
    }

    /// Inserts or overwrites `key`, marking it as most recently used and
    /// evicting the least recently used entry if over capacity.
    pub fn put(self: *Lru, gpa: Allocator, key: []const u8, value: []const u8) Allocator.Error!void {
        const gop = try self.map.getOrPut(gpa, key);
        if (gop.found_existing) {
            self.nodes.items[gop.value_ptr.*].value = value;
            self.moveToFront(gop.value_ptr.*);
            return;
        }
        const idx = self.allocNode(gpa) catch |err| {
            self.map.removeByPtr(gop.key_ptr);
            return err;
        };
        self.nodes.items[idx] = .{ .key = key, .value = value, .prev = none, .next = none };
        gop.value_ptr.* = idx;
        self.pushFront(idx);

        if (self.map.count() > self.capacity) {
            const lru = self.tail;
            _ = self.map.remove(self.nodes.items[lru].key);
            self.unlink(lru);
            self.freeNode(lru);
            self.noteRemoval();
        }
    }

    /// Removes `key`. Returns whether it was present.
    pub fn remove(self: *Lru, key: []const u8) bool {
        const kv = self.map.fetchRemove(key) orelse return false;
        self.unlink(kv.value);
        self.freeNode(kv.value);
        self.noteRemoval();
        return true;
    }

    /// The std hash map deletes with tombstones and only clears them when it
    /// grows. A cache at steady state never grows, so tombstones would pile
    /// up until lookups of absent keys scan the whole table. Rehashing after
    /// every capacity/8 removals bounds them while keeping removal O(1)
    /// amortized.
    fn noteRemoval(self: *Lru) void {
        self.removals += 1;
        if (self.removals >= self.map.capacity() / 8) {
            self.map.rehash(std.hash_map.StringContext{});
            self.removals = 0;
        }
    }

    fn allocNode(self: *Lru, gpa: Allocator) Allocator.Error!Index {
        if (self.free != none) {
            const idx = self.free;
            self.free = self.nodes.items[idx].next;
            return idx;
        }
        const idx: Index = @intCast(self.nodes.items.len);
        _ = try self.nodes.addOne(gpa);
        return idx;
    }

    fn freeNode(self: *Lru, idx: Index) void {
        self.nodes.items[idx].next = self.free;
        self.free = idx;
    }

    fn unlink(self: *Lru, idx: Index) void {
        const node = &self.nodes.items[idx];
        if (node.prev != none) self.nodes.items[node.prev].next = node.next else self.head = node.next;
        if (node.next != none) self.nodes.items[node.next].prev = node.prev else self.tail = node.prev;
        node.prev = none;
        node.next = none;
    }

    fn pushFront(self: *Lru, idx: Index) void {
        const node = &self.nodes.items[idx];
        node.prev = none;
        node.next = self.head;
        if (self.head != none) self.nodes.items[self.head].prev = idx else self.tail = idx;
        self.head = idx;
    }

    fn moveToFront(self: *Lru, idx: Index) void {
        if (self.head == idx) return;
        self.unlink(idx);
        self.pushFront(idx);
    }
};

/// Splits input into lines terminated by "\n", "\r" or "\r\n".
const LineIterator = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn next(self: *LineIterator) ?[]const u8 {
        if (self.pos >= self.bytes.len) return null;
        const rest = self.bytes[self.pos..];
        const end = std.mem.indexOfAny(u8, rest, "\r\n") orelse {
            self.pos = self.bytes.len;
            return rest;
        };
        self.pos += end + 1;
        if (rest[end] == '\r' and end + 1 < rest.len and rest[end + 1] == '\n') self.pos += 1;
        return rest[0..end];
    }
};

/// Characters stripped from the capacity line (ASCII control chars and space).
const trim_chars = blk: {
    var chars: [33]u8 = undefined;
    for (&chars, 0..) |*c, i| c.* = i;
    break :blk chars;
};

/// Executes one command line against the cache. Malformed or unknown
/// commands are ignored.
fn execute(cache: *Lru, gpa: Allocator, out: *Io.Writer, line: []const u8) !void {
    const sp = std.mem.indexOfScalar(u8, line, ' ');
    const cmd = if (sp) |i| line[0..i] else line;
    // Single-argument commands take the remainder of the line as the key.
    const arg = if (sp) |i| line[i + 1 ..] else line;

    if (std.mem.eql(u8, cmd, "SET")) {
        const i = std.mem.indexOfScalar(u8, arg, ' ') orelse return;
        try cache.put(gpa, arg[0..i], arg[i + 1 ..]);
    } else if (std.mem.eql(u8, cmd, "GET")) {
        try out.writeAll(cache.get(arg) orelse "NULL");
        try out.writeByte('\n');
    } else if (std.mem.eql(u8, cmd, "DEL")) {
        try out.writeAll(if (cache.remove(arg)) "1\n" else "0\n");
    } else if (std.mem.eql(u8, cmd, "SIZE")) {
        try out.print("{d}\n", .{cache.count()});
    }
}

/// Processes a complete input, writing results to `out`.
/// All keys and values borrow from `input`.
pub fn run(gpa: Allocator, input: []const u8, out: *Io.Writer) !void {
    var lines: LineIterator = .{ .bytes = input };
    const first = lines.next() orelse return;
    const capacity = try std.fmt.parseInt(usize, std.mem.trim(u8, first, &trim_chars), 10);

    var cache = try Lru.init(gpa, capacity);
    defer cache.deinit(gpa);

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try execute(&cache, gpa, out, line);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var in_buf: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
    const input = try stdin.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(input);

    var out_buf: [1024 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    try run(gpa, input, &stdout.interface);
    try stdout.interface.flush();
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
    try expectRun("3\nSET x 1\nDEL x\nDEL x\nSIZE\nGET x\n", "1\n0\n0\nNULL\n");
}

test "capacity one, CRLF, blank lines, missing final newline" {
    try expectRun("1\r\nSET a 1\r\n\r\nSET b 2\nGET a\nGET b\nSIZE", "NULL\n2\n1\n");
}

test "node reuse after eviction and deletion" {
    try expectRun("2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n", "1\nNULL\n3\n4\n2\n");
}

test "empty input" {
    try expectRun("", "");
}
