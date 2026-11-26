//! Thread-safe in-memory key-value store. Keys are byte strings, values are
//! arbitrary byte sequences. All memory is owned by the store's allocator.
const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

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

/// Stores `value` under `key`. On success the store takes ownership of
/// `value`, which must have been allocated with the store's allocator; on
/// error the caller keeps ownership.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
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

/// Returns a copy of the value stored under `key`, allocated with `gpa`, or
/// null when the key is absent.
pub fn get(s: *Store, io: Io, gpa: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn delete(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    const removed = blk: {
        try s.lock.lock(io);
        defer s.lock.unlock(io);
        break :blk s.map.fetchRemove(key) orelse return false;
    };
    s.gpa.free(removed.key);
    s.gpa.free(removed.value);
    return true;
}

/// Returns a snapshot of every key, sorted ascending. The slice and the keys
/// are allocated with `arena`; free them by resetting the arena.
pub fn listKeys(s: *Store, io: Io, arena: Allocator) (Allocator.Error || Io.Cancelable)![]const []const u8 {
    const keys = blk: {
        try s.lock.lockShared(io);
        defer s.lock.unlockShared(io);

        const keys = try arena.alloc([]const u8, s.map.count());
        var it = s.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| : (i += 1) keys[i] = try arena.dupe(u8, key.*);
        break :blk keys;
    };
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, delete, list" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var s: Store = .init(gpa);
    defer s.deinit();

    try std.testing.expectEqual(.created, try s.put(io, "b", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try s.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try s.put(io, "a", try gpa.dupe(u8, "")));

    const v = (try s.get(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("2", v);
    try std.testing.expectEqual(null, try s.get(io, gpa, "zz"));

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const keys = try s.listKeys(io, arena.allocator());
    try std.testing.expectEqual(2, keys.len);
    try std.testing.expectEqualStrings("a", keys[0]);
    try std.testing.expectEqualStrings("b", keys[1]);

    try std.testing.expect(try s.delete(io, "a"));
    try std.testing.expect(!try s.delete(io, "a"));
}
