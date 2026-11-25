//! Thread-safe in-memory key-value store. Keys and values are owned by the store.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
mutex: Io.Mutex = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub const PutResult = enum { created, replaced };

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(s: *Store) void {
    var it = s.map.iterator();
    while (it.next()) |e| {
        s.gpa.free(e.key_ptr.*);
        s.gpa.free(e.value_ptr.*);
    }
    s.map.deinit(s.gpa);
    s.* = undefined;
}

/// Stores `value`, taking ownership of it; it must have been allocated with
/// the store's allocator. On error, ownership stays with the caller.
pub fn putOwned(s: *Store, io: Io, key: []const u8, value: []u8) Allocator.Error!PutResult {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

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

/// Returns a copy of the value owned by `gpa`, or null if absent.
pub fn getCopy(s: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Returns true if the key existed.
pub fn remove(s: *Store, io: Io, key: []const u8) bool {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Returns every key, sorted ascending. Caller frees the outer slice and
/// each key with `gpa`.
pub fn sortedKeys(s: *Store, io: Io, gpa: Allocator) Allocator.Error![][]u8 {
    var keys: std.ArrayList([]u8) = .empty;
    errdefer {
        for (keys.items) |k| gpa.free(k);
        keys.deinit(gpa);
    }
    {
        s.mutex.lockUncancelable(io);
        defer s.mutex.unlock(io);

        try keys.ensureTotalCapacityPrecise(gpa, s.map.count());
        var it = s.map.keyIterator();
        while (it.next()) |k| keys.appendAssumeCapacity(try gpa.dupe(u8, k.*));
    }
    std.mem.sortUnstable([]u8, keys.items, {}, lessThan);
    return keys.toOwnedSlice(gpa);
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn freeKeys(gpa: Allocator, keys: [][]u8) void {
    for (keys) |k| gpa.free(k);
    gpa.free(keys);
}

test "put get remove list" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var s: Store = .init(gpa);
    defer s.deinit();

    try std.testing.expectEqual(.created, try s.putOwned(io, "b", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try s.putOwned(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try s.putOwned(io, "a", try gpa.dupe(u8, "")));

    const v = (try s.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("2", v);
    try std.testing.expectEqual(null, try s.getCopy(io, gpa, "zz"));

    const keys = try s.sortedKeys(io, gpa);
    defer freeKeys(gpa, keys);
    try std.testing.expectEqual(2, keys.len);
    try std.testing.expectEqualStrings("a", keys[0]);
    try std.testing.expectEqualStrings("b", keys[1]);

    try std.testing.expect(s.remove(io, "a"));
    try std.testing.expect(!s.remove(io, "a"));
}
