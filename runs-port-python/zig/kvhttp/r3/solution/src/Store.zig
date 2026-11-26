//! Thread-safe in-memory key-value store.
//!
//! The store owns copies of every key and value it holds. All access is
//! serialized by a single mutex; critical sections never perform I/O, so
//! contention stays low even with many concurrent connections.

const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

gpa: Allocator,
mutex: Io.Mutex = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub const PutResult = enum { created, replaced };

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

/// Stores a copy of `value` under `key`, replacing any previous value.
pub fn put(s: *Store, io: Io, key: []const u8, value: []const u8) (Allocator.Error || Io.Cancelable)!PutResult {
    // Copy outside the lock; large values should not stall other clients.
    const owned_value = try s.gpa.dupe(u8, value);
    errdefer s.gpa.free(owned_value);
    const owned_key = try s.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) s.gpa.free(owned_key);

    const old_value: ?[]u8 = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        const gop = try s.map.getOrPut(s.gpa, owned_key);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = owned_value;
            break :blk old;
        }
        key_used = true;
        gop.value_ptr.* = owned_value;
        break :blk null;
    };

    if (old_value) |old| {
        s.gpa.free(old);
        return .replaced;
    }
    return .created;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`,
/// or null if the key is absent.
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
    const kv = removed orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Returns copies of all keys, sorted ascending by byte value, allocated with
/// `allocator`. The caller owns the returned slice and its elements.
pub fn sortedKeys(s: *Store, io: Io, allocator: Allocator) (Allocator.Error || Io.Cancelable)![][]const u8 {
    const keys = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        const keys = try allocator.alloc([]const u8, s.map.count());
        var filled: usize = 0;
        errdefer {
            for (keys[0..filled]) |k| allocator.free(k);
            allocator.free(keys);
        }
        var it = s.map.keyIterator();
        while (it.next()) |key| : (filled += 1) {
            keys[filled] = try allocator.dupe(u8, key.*);
        }
        break :blk keys;
    };
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, get, replace, delete" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "a", "hello"));
    try std.testing.expectEqual(.replaced, try store.put(io, "a", "world"));

    const value = (try store.get(io, gpa, "a")).?;
    defer gpa.free(value);
    try std.testing.expectEqualStrings("world", value);

    try std.testing.expect(try store.delete(io, "a"));
    try std.testing.expect(!try store.delete(io, "a"));
    try std.testing.expectEqual(null, try store.get(io, gpa, "a"));
}

test "sortedKeys" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "-" }) |k| _ = try store.put(io, k, "");
    const keys = try store.sortedKeys(io, gpa);
    defer {
        for (keys) |k| gpa.free(k);
        gpa.free(keys);
    }
    const expected = [_][]const u8{ "-", "C", "_", "a", "b" };
    try std.testing.expectEqual(expected.len, keys.len);
    for (expected, keys) |e, k| try std.testing.expectEqualStrings(e, k);
}
