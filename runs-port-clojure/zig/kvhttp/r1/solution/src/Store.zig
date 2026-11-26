//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned copies; readers receive their own copy of a value
//! so that concurrent replacement or deletion can never invalidate it.

const Store = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

gpa: Allocator,
lock: Io.RwLock = .init,
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

/// Stores a copy of `value` under `key`. Returns true if the key was new.
pub fn put(s: *Store, io: Io, key: []const u8, value: []const u8) Allocator.Error!bool {
    const value_copy = try s.gpa.dupe(u8, value);
    errdefer s.gpa.free(value_copy);

    s.lock.lockUncancelable(io);
    defer s.lock.unlock(io);

    const gop = try s.map.getOrPut(s.gpa, key);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value_copy;
        return false;
    }
    gop.key_ptr.* = s.gpa.dupe(u8, key) catch |err| {
        s.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value_copy;
    return true;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`,
/// or null if the key is absent.
pub fn get(s: *Store, io: Io, allocator: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    s.lock.lockSharedUncancelable(io);
    defer s.lock.unlockShared(io);

    const value = s.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`. Returns true if it was present.
pub fn delete(s: *Store, io: Io, key: []const u8) bool {
    s.lock.lockUncancelable(io);
    defer s.lock.unlock(io);

    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Returns a copy of every key, sorted ascending by byte order. The outer
/// slice and every key are allocated with `allocator`.
pub fn sortedKeys(s: *Store, io: Io, allocator: Allocator) Allocator.Error![][]u8 {
    const keys = blk: {
        s.lock.lockSharedUncancelable(io);
        defer s.lock.unlockShared(io);

        const keys = try allocator.alloc([]u8, s.map.count());
        var filled: usize = 0;
        errdefer {
            for (keys[0..filled]) |k| allocator.free(k);
            allocator.free(keys);
        }
        var it = s.map.keyIterator();
        while (it.next()) |k| : (filled += 1) keys[filled] = try allocator.dupe(u8, k.*);
        break :blk keys;
    };
    std.mem.sortUnstable([]u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, replace, delete" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var s: Store = .init(std.testing.allocator);
    defer s.deinit();

    try std.testing.expect(try s.put(io, "a", "hello"));
    try std.testing.expectEqualStrings("hello", (try s.get(io, arena.allocator(), "a")).?);
    try std.testing.expect(!try s.put(io, "a", "world"));
    try std.testing.expectEqualStrings("world", (try s.get(io, arena.allocator(), "a")).?);
    try std.testing.expect(s.delete(io, "a"));
    try std.testing.expectEqual(null, try s.get(io, arena.allocator(), "a"));
    try std.testing.expect(!s.delete(io, "a"));
}

test "sortedKeys" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var s: Store = .init(std.testing.allocator);
    defer s.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "aa" }) |k| _ = try s.put(io, k, k);
    const keys = try s.sortedKeys(io, arena.allocator());
    try std.testing.expectEqual(5, keys.len);
    const want = [_][]const u8{ "C", "_", "a", "aa", "b" };
    for (want, keys) |w, k| try std.testing.expectEqualStrings(w, k);
}
