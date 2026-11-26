//! Thread-safe in-memory key-value store. Keys and values are owned copies.

const Store = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

gpa: Allocator,
lock: Io.RwLock = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub const PutResult = enum { created, replaced };

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(store: *Store) void {
    var it = store.map.iterator();
    while (it.next()) |entry| {
        store.gpa.free(entry.key_ptr.*);
        store.gpa.free(entry.value_ptr.*);
    }
    store.map.deinit(store.gpa);
    store.* = undefined;
}

/// Stores a copy of `value` under `key`. On failure the store is unchanged.
pub fn put(store: *Store, io: Io, key: []const u8, value: []const u8) Allocator.Error!PutResult {
    const copy = try store.gpa.dupe(u8, value);
    errdefer store.gpa.free(copy);

    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = copy;
        return .replaced;
    }
    gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
        store.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = copy;
    return .created;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`,
/// or null if the key is absent.
pub fn get(store: *Store, io: Io, allocator: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`. Returns true if it was present.
pub fn delete(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Returns copies of every key, sorted ascending, allocated with `allocator`.
pub fn sortedKeys(store: *Store, io: Io, allocator: Allocator) Allocator.Error![]const []const u8 {
    const keys = blk: {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);

        const keys = try allocator.alloc([]const u8, store.map.count());
        var it = store.map.keyIterator();
        for (keys) |*k| k.* = try allocator.dupe(u8, it.next().?.*);
        break :blk keys;
    };
    std.mem.sort([]const u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test "put, get, delete, list" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expectEqual(PutResult.created, try store.put(io, "b", "2"));
    try testing.expectEqual(PutResult.created, try store.put(io, "a", "1"));
    try testing.expectEqual(PutResult.replaced, try store.put(io, "b", "two"));

    const value = (try store.get(io, testing.allocator, "b")).?;
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("two", value);
    try testing.expectEqual(null, try store.get(io, testing.allocator, "zz"));

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const keys = try store.sortedKeys(io, arena.allocator());
    try testing.expectEqual(@as(usize, 2), keys.len);
    try testing.expectEqualStrings("a", keys[0]);
    try testing.expectEqualStrings("b", keys[1]);

    try testing.expect(store.delete(io, "a"));
    try testing.expect(!store.delete(io, "a"));
}
