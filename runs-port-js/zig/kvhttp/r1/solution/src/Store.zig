//! Thread-safe in-memory key-value store. Keys and values are owned by the
//! store; readers receive copies so no lock is held while responding.

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

/// Stores `value`, taking ownership of it. `value` must have been allocated
/// with the store's allocator. On error, ownership stays with the caller.
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

/// Returns a copy of the value for `key`, allocated with `allocator`.
pub fn get(store: *Store, io: Io, allocator: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Returns whether the key was present.
pub fn remove(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const entry = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(entry.key);
    store.gpa.free(entry.value);
    return true;
}

/// Returns copies of every key in ascending byte order, allocated with `allocator`.
pub fn sortedKeys(store: *Store, io: Io, allocator: Allocator) Allocator.Error![][]const u8 {
    const keys = blk: {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);

        const keys = try allocator.alloc([]const u8, store.map.count());
        var it = store.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| : (i += 1) keys[i] = try allocator.dupe(u8, key.*);
        break :blk keys;
    };
    std.mem.sort([]const u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove, list" {
    const io = std.testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "b", try std.testing.allocator.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "b", try std.testing.allocator.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.put(io, "a", try std.testing.allocator.dupe(u8, "")));
    try std.testing.expectEqualStrings("2", (try store.get(io, arena, "b")).?);
    try std.testing.expectEqualStrings("", (try store.get(io, arena, "a")).?);
    try std.testing.expectEqual(null, try store.get(io, arena, "c"));

    const keys = try store.sortedKeys(io, arena);
    try std.testing.expectEqual(2, keys.len);
    try std.testing.expectEqualStrings("a", keys[0]);
    try std.testing.expectEqualStrings("b", keys[1]);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
}
