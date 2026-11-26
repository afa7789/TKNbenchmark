//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store (allocated with `gpa`). Readers get
//! copies allocated from a caller-supplied allocator, so the lock is never held
//! while a response is being written to a slow client.

const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

gpa: Allocator,
mutex: Io.Mutex = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(s: *Store) void {
    var it = s.map.iterator();
    while (it.next()) |entry| {
        s.gpa.free(entry.key_ptr.*);
        s.gpa.free(entry.value_ptr.*);
    }
    s.map.deinit(s.gpa);
    s.* = undefined;
}

pub const PutResult = enum { created, replaced };

/// Stores a copy of `value` under `key`.
pub fn put(s: *Store, io: Io, key: []const u8, value: []const u8) (Allocator.Error || Io.Cancelable)!PutResult {
    // Allocate outside the critical section.
    const owned_value = try s.gpa.dupe(u8, value);
    errdefer s.gpa.free(owned_value);

    const old_value: ?[]u8, const result: PutResult = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);

        const gop = try s.map.getOrPut(s.gpa, key);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = owned_value;
            break :blk .{ old, .replaced };
        }
        gop.key_ptr.* = s.gpa.dupe(u8, key) catch |err| {
            s.map.removeByPtr(gop.key_ptr);
            return err;
        };
        gop.value_ptr.* = owned_value;
        break :blk .{ null, .created };
    };

    if (old_value) |old| s.gpa.free(old);
    return result;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`.
pub fn get(s: *Store, io: Io, allocator: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);

    const value = s.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn delete(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    const removed = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        break :blk s.map.fetchRemove(key);
    };
    const entry = removed orelse return false;
    s.gpa.free(entry.key);
    s.gpa.free(entry.value);
    return true;
}

/// Returns copies of every key, sorted ascending by byte value.
pub fn keys(s: *Store, io: Io, allocator: Allocator) (Allocator.Error || Io.Cancelable)![][]const u8 {
    const list = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);

        const list = try allocator.alloc([]const u8, s.map.count());
        errdefer allocator.free(list);
        var it = s.map.keyIterator();
        var i: usize = 0;
        errdefer for (list[0..i]) |k| allocator.free(k);
        while (it.next()) |key| : (i += 1) {
            list[i] = try allocator.dupe(u8, key.*);
        }
        break :blk list;
    };
    std.mem.sortUnstable([]const u8, list, {}, lessThan);
    return list;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, delete, keys" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    try std.testing.expectEqual(PutResult.created, try store.put(io, "b", "1"));
    try std.testing.expectEqual(PutResult.replaced, try store.put(io, "b", "2"));
    try std.testing.expectEqual(PutResult.created, try store.put(io, "a", ""));
    try std.testing.expectEqualStrings("2", (try store.get(io, a, "b")).?);
    try std.testing.expectEqualStrings("", (try store.get(io, a, "a")).?);
    try std.testing.expectEqual(null, try store.get(io, a, "c"));

    const ks = try store.keys(io, a);
    try std.testing.expectEqual(2, ks.len);
    try std.testing.expectEqualStrings("a", ks[0]);
    try std.testing.expectEqualStrings("b", ks[1]);

    try std.testing.expect(try store.delete(io, "b"));
    try std.testing.expect(!try store.delete(io, "b"));
    try std.testing.expectEqual(null, try store.get(io, a, "b"));
}
