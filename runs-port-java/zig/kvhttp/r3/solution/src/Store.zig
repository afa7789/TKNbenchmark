//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store and allocated with `gpa`.
//! Readers receive copies so that no lock is held while a response is written.

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

/// Stores `value` under `key`, taking ownership of `value`, which must have
/// been allocated with the store's allocator. On error, ownership of `value`
/// remains with the caller.
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

/// Returns a copy of the value stored under `key`, allocated with `gpa`,
/// or `null` if the key is absent.
pub fn get(s: *Store, io: Io, gpa: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`. Returns whether it was present.
pub fn remove(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const entry = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(entry.key);
    s.gpa.free(entry.value);
    return true;
}

/// Returns every key, sorted ascending, as a JSON array allocated with `gpa`.
pub fn keysJson(s: *Store, io: Io, gpa: Allocator) (Allocator.Error || Io.Cancelable)![]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const keys = try gpa.alloc([]const u8, s.map.count());
    defer gpa.free(keys);
    var it = s.map.keyIterator();
    for (keys) |*k| k.* = it.next().?.*;
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);

    var out: Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    w.writeByte('[') catch return error.OutOfMemory;
    for (keys, 0..) |key, i| {
        if (i != 0) w.writeByte(',') catch return error.OutOfMemory;
        // Keys are restricted to [A-Za-z0-9_-], so they never need escaping.
        w.print("\"{s}\"", .{key}) catch return error.OutOfMemory;
    }
    w.writeByte(']') catch return error.OutOfMemory;
    return try out.toOwnedSlice();
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test "put, get, replace, remove" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expectEqual(PutResult.created, try store.put(io, "a", try testing.allocator.dupe(u8, "hello")));
    try testing.expectEqual(PutResult.replaced, try store.put(io, "a", try testing.allocator.dupe(u8, "world")));

    const value = (try store.get(io, testing.allocator, "a")).?;
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("world", value);

    try testing.expect(try store.remove(io, "a"));
    try testing.expect(!try store.remove(io, "a"));
    try testing.expectEqual(null, try store.get(io, testing.allocator, "a"));
}

test "keysJson sorts keys" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    {
        const empty = try store.keysJson(io, testing.allocator);
        defer testing.allocator.free(empty);
        try testing.expectEqualStrings("[]", empty);
    }

    for ([_][]const u8{ "b", "a", "_", "C", "a-1" }) |key| {
        _ = try store.put(io, key, try testing.allocator.alloc(u8, 0));
    }
    const json = try store.keysJson(io, testing.allocator);
    defer testing.allocator.free(json);
    try testing.expectEqualStrings("[\"C\",\"_\",\"a\",\"a-1\",\"b\"]", json);
}
