//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store. Readers receive copies so that
//! concurrent writers can free replaced values without coordination.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
lock: Io.RwLock = .init,
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

/// Stores `value` under `key`. Ownership of `value` (allocated with the
/// store's allocator) passes to the store, even on error.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) !PutResult {
    errdefer s.gpa.free(value);

    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const gop = try s.map.getOrPut(s.gpa, key);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = s.gpa.dupe(u8, key) catch |err| {
        s.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value;
    return .created;
}

/// Returns a copy of the value stored under `key`, allocated with `gpa`,
/// or null if the key is absent.
pub fn fetch(s: *Store, io: Io, gpa: Allocator, key: []const u8) !?[]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`. Returns true if it was present.
pub fn delete(s: *Store, io: Io, key: []const u8) !bool {
    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// A sorted snapshot of the store's keys. The key slices point into `bytes`.
pub const KeyList = struct {
    keys: [][]const u8,
    bytes: []u8,

    pub fn deinit(kl: *KeyList, gpa: Allocator) void {
        gpa.free(kl.keys);
        gpa.free(kl.bytes);
        kl.* = undefined;
    }
};

/// Returns a snapshot of all keys in ascending byte order, allocated with `gpa`.
pub fn listKeys(s: *Store, io: Io, gpa: Allocator) !KeyList {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    var total: usize = 0;
    var it = s.map.keyIterator();
    while (it.next()) |k| total += k.len;

    const keys = try gpa.alloc([]const u8, s.map.count());
    errdefer gpa.free(keys);
    const bytes = try gpa.alloc(u8, total);

    var offset: usize = 0;
    it = s.map.keyIterator();
    for (keys) |*slot| {
        const k = it.next().?.*;
        const dest = bytes[offset..][0..k.len];
        @memcpy(dest, k);
        slot.* = dest;
        offset += k.len;
    }

    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    return .{ .keys = keys, .bytes = bytes };
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, fetch, delete, list" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "b", try gpa.dupe(u8, "3")));

    const v = (try store.fetch(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("3", v);
    try std.testing.expectEqual(null, try store.fetch(io, gpa, "zz"));

    var list = try store.listKeys(io, gpa);
    defer list.deinit(gpa);
    try std.testing.expectEqual(2, list.keys.len);
    try std.testing.expectEqualStrings("a", list.keys[0]);
    try std.testing.expectEqualStrings("b", list.keys[1]);

    try std.testing.expect(try store.delete(io, "a"));
    try std.testing.expect(!try store.delete(io, "a"));
}
