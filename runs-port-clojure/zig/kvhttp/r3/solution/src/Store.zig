//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store. Readers receive copies so that no
//! lock is held while a response is written to a (possibly slow) client.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Store = @This();

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

/// Returns a copy of the value stored under `key`, owned by `gpa`, or null.
pub fn fetch(store: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);
    const value = store.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Stores a copy of `value` under `key`.
pub fn put(store: *Store, io: Io, key: []const u8, value: []const u8) Allocator.Error!PutResult {
    const owned_value = try store.gpa.dupe(u8, value);
    errdefer store.gpa.free(owned_value);
    // Allocate the key outside the critical section; it is freed again if
    // the key turns out to exist already.
    const owned_key = try store.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) store.gpa.free(owned_key);

    var old_value: ?[]u8 = null;
    defer if (old_value) |v| store.gpa.free(v);

    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, owned_key);
    if (gop.found_existing) {
        old_value = gop.value_ptr.*;
        gop.value_ptr.* = owned_value;
        return .replaced;
    }
    key_used = true;
    gop.value_ptr.* = owned_value;
    return .created;
}

/// Removes `key`. Returns true if it was present.
pub fn delete(store: *Store, io: Io, key: []const u8) bool {
    const kv = blk: {
        store.lock.lockUncancelable(io);
        defer store.lock.unlock(io);
        break :blk store.map.fetchRemove(key) orelse return false;
    };
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Returns every key sorted ascending. The outer slice and every key are
/// owned by `gpa`; free them with `freeKeys`.
pub fn listKeys(store: *Store, io: Io, gpa: Allocator) Allocator.Error![][]u8 {
    var keys: std.ArrayList([]u8) = .empty;
    errdefer {
        freeKeys(gpa, keys.items);
        keys.deinit(gpa);
    }
    {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);
        try keys.ensureTotalCapacityPrecise(gpa, store.map.count());
        var it = store.map.keyIterator();
        while (it.next()) |key| keys.appendAssumeCapacity(try gpa.dupe(u8, key.*));
    }
    std.mem.sortUnstable([]u8, keys.items, {}, lessThan);
    return keys.toOwnedSlice(gpa);
}

pub fn freeKeys(gpa: Allocator, keys: []const []u8) void {
    for (keys) |key| gpa.free(key);
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, fetch, delete, list" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(PutResult.created, try store.put(io, "b", "2"));
    try std.testing.expectEqual(PutResult.created, try store.put(io, "a", "1"));
    try std.testing.expectEqual(PutResult.replaced, try store.put(io, "a", "one"));

    const value = (try store.fetch(io, gpa, "a")).?;
    defer gpa.free(value);
    try std.testing.expectEqualStrings("one", value);
    try std.testing.expectEqual(null, try store.fetch(io, gpa, "zz"));

    const keys = try store.listKeys(io, gpa);
    defer {
        freeKeys(gpa, keys);
        gpa.free(keys);
    }
    try std.testing.expectEqual(2, keys.len);
    try std.testing.expectEqualStrings("a", keys[0]);
    try std.testing.expectEqualStrings("b", keys[1]);

    try std.testing.expect(store.delete(io, "a"));
    try std.testing.expect(!store.delete(io, "a"));
}
