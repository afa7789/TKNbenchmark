//! Thread-safe in-memory key-value store holding raw byte values.
//!
//! The store owns copies of all keys and values. Readers receive their own
//! copy of a value so that no lock is held while it is sent over the network.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
lock: Io.RwLock = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

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

pub const PutResult = enum { created, replaced };

/// Stores `value`, taking ownership of it (it must have been allocated with
/// the store's allocator). The key is copied.
pub fn put(store: *Store, io: Io, key: []const u8, value: []u8) Allocator.Error!PutResult {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
        store.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value;
    return .created;
}

/// Returns a copy of the value stored under `key`, owned by the caller and
/// allocated with `gpa`, or null if the key is absent.
pub fn getCopy(store: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn delete(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Returns copies of all keys sorted ascending by byte value. Free the result
/// with `freeKeys`.
pub fn keys(store: *Store, io: Io, gpa: Allocator) Allocator.Error![][]u8 {
    const list = blk: {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);

        const list = try gpa.alloc([]u8, store.map.count());
        var filled: usize = 0;
        errdefer freeKeys(gpa, list[0..filled]);
        var it = store.map.keyIterator();
        while (it.next()) |key| : (filled += 1) {
            list[filled] = try gpa.dupe(u8, key.*);
        }
        break :blk list;
    };
    std.mem.sort([]u8, list, {}, lessThan);
    return list;
}

pub fn freeKeys(gpa: Allocator, list: []const []u8) void {
    for (list) |key| gpa.free(key);
    gpa.free(list);
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, get, delete, keys" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(PutResult.created, try store.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(PutResult.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(PutResult.replaced, try store.put(io, "b", try gpa.dupe(u8, "3")));

    const value = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(value);
    try std.testing.expectEqualStrings("3", value);
    try std.testing.expectEqual(null, try store.getCopy(io, gpa, "zz"));

    const list = try store.keys(io, gpa);
    defer freeKeys(gpa, list);
    try std.testing.expectEqual(2, list.len);
    try std.testing.expectEqualStrings("a", list[0]);
    try std.testing.expectEqualStrings("b", list[1]);

    try std.testing.expect(store.delete(io, "a"));
    try std.testing.expect(!store.delete(io, "a"));
}
