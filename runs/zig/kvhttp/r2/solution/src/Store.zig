//! Thread-safe in-memory key-value store. Keys and values are owned copies.

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

/// Returns a copy of the value for `key`, owned by the caller and allocated
/// with `gpa`, or null if absent.
pub fn getCopy(store: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Returns true if the key existed and was removed.
pub fn remove(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Writes all keys, sorted ascending, as a JSON array of strings into a
/// caller-owned buffer allocated with `gpa`.
pub fn keysJson(store: *Store, io: Io, gpa: Allocator) Allocator.Error![]u8 {
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);

        const keys = try gpa.alloc([]const u8, store.map.count());
        defer gpa.free(keys);
        var it = store.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |k| : (i += 1) keys[i] = k.*;

        std.mem.sortUnstable([]const u8, keys, {}, lessThan);

        // Keys are restricted to [A-Za-z0-9_-], so no JSON escaping is needed.
        const w = &out.writer;
        w.writeByte('[') catch return error.OutOfMemory;
        for (keys, 0..) |k, j| {
            if (j != 0) w.writeByte(',') catch return error.OutOfMemory;
            w.writeByte('"') catch return error.OutOfMemory;
            w.writeAll(k) catch return error.OutOfMemory;
            w.writeByte('"') catch return error.OutOfMemory;
        }
        w.writeByte(']') catch return error.OutOfMemory;
    }

    return out.toOwnedSlice();
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove, list" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "b", try gpa.dupe(u8, "3")));

    const v = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("3", v);

    const json = try store.keysJson(io, gpa);
    defer gpa.free(json);
    try std.testing.expectEqualStrings("[\"a\",\"b\"]", json);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
    try std.testing.expectEqual(null, try store.getCopy(io, gpa, "a"));
}
