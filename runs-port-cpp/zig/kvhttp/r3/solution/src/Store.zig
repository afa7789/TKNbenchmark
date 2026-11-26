//! Thread-safe in-memory key/value store.
//!
//! Keys and values are owned by the store. Readers receive copies so the lock
//! is never held while a response is being written to a (possibly slow) peer.

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

/// Stores a copy of `value` under `key`.
pub fn put(store: *Store, io: Io, key: []const u8, value: []const u8) Allocator.Error!PutResult {
    const owned_value = try store.gpa.dupe(u8, value);
    errdefer store.gpa.free(owned_value);

    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = owned_value;
        return .replaced;
    }
    gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
        store.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = owned_value;
    return .created;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`.
pub fn get(store: *Store, io: Io, allocator: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn remove(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const entry = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(entry.key);
    store.gpa.free(entry.value);
    return true;
}

/// Returns copies of every key in ascending byte order, allocated with `allocator`.
pub fn keys(store: *Store, io: Io, allocator: Allocator) Allocator.Error![]const []const u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const out = try allocator.alloc([]const u8, store.map.count());
    var it = store.map.keyIterator();
    var i: usize = 0;
    while (it.next()) |key| : (i += 1) {
        out[i] = try allocator.dupe(u8, key.*);
    }
    std.mem.sortUnstable([]const u8, out, {}, lessThan);
    return out;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove and sorted keys" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    try std.testing.expectEqual(PutResult.created, try store.put(io, "b", "2"));
    try std.testing.expectEqual(PutResult.created, try store.put(io, "a", "1"));
    try std.testing.expectEqual(PutResult.replaced, try store.put(io, "b", "two"));
    try std.testing.expectEqualStrings("two", (try store.get(io, arena.allocator(), "b")).?);

    const listed = try store.keys(io, arena.allocator());
    try std.testing.expectEqual(2, listed.len);
    try std.testing.expectEqualStrings("a", listed[0]);
    try std.testing.expectEqualStrings("b", listed[1]);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
    try std.testing.expectEqual(null, try store.get(io, arena.allocator(), "a"));
}
