//! Thread-safe in-memory key/value store.
//!
//! Keys and values are owned by the store and allocated with `gpa`. Readers
//! receive copies so that no lock is held while data is written to a socket.

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

/// Stores `value` under `key`. On success the store takes ownership of
/// `value`, which must have been allocated with `s.gpa`. On error the caller
/// keeps ownership.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    // Allocate the key copy outside the critical section.
    const owned_key = try s.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) s.gpa.free(owned_key);

    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const gop = try s.map.getOrPut(s.gpa, key);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = owned_key;
    gop.value_ptr.* = value;
    key_used = true;
    return .created;
}

/// Returns a copy of the value stored under `key`, allocated with `gpa`, or
/// null if the key is absent.
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
    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Returns every key, sorted ascending, as a JSON array. Caller owns the
/// returned memory, allocated with `gpa`.
pub fn keysJson(s: *Store, io: Io, gpa: Allocator) (Allocator.Error || Io.Cancelable)![]u8 {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const keys = blk: {
        try s.lock.lockShared(io);
        defer s.lock.unlockShared(io);
        const keys = try arena.alloc([]const u8, s.map.count());
        var it = s.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |k| : (i += 1) keys[i] = try arena.dupe(u8, k.*);
        break :blk keys;
    };

    std.mem.sort([]const u8, keys, {}, lessThan);
    return std.json.Stringify.valueAlloc(gpa, keys, .{});
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put get remove" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(PutResult.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(PutResult.replaced, try store.put(io, "a", try gpa.dupe(u8, "2")));

    const got = (try store.get(io, gpa, "a")).?;
    defer gpa.free(got);
    try std.testing.expectEqualStrings("2", got);

    try std.testing.expect(try store.remove(io, "a"));
    try std.testing.expect(!try store.remove(io, "a"));
    try std.testing.expectEqual(null, try store.get(io, gpa, "a"));
}

test "keys are sorted" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "C", "_" }) |k| _ = try store.put(io, k, try gpa.dupe(u8, "v"));
    const json = try store.keysJson(io, gpa);
    defer gpa.free(json);
    try std.testing.expectEqualStrings("[\"C\",\"_\",\"a\",\"b\"]", json);

    var empty: Store = .init(gpa);
    defer empty.deinit();
    const none = try empty.keysJson(io, gpa);
    defer gpa.free(none);
    try std.testing.expectEqualStrings("[]", none);
}
