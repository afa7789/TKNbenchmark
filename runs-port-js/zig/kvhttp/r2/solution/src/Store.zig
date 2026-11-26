//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store. Readers receive copies so that no
//! lock is held while a response is being written to a (possibly slow) client.

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

/// Stores `value` under `key`. On success the store takes ownership of
/// `value`, which must have been allocated with the store's allocator.
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

/// Returns a copy of the value stored under `key`, allocated with `gpa`, or
/// null if the key is absent.
pub fn get(store: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`. Returns whether it was present.
pub fn remove(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    defer store.lock.unlock(io);

    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Writes every key, sorted ascending by byte value, as a JSON array of strings.
pub fn writeKeysJson(store: *Store, io: Io, gpa: Allocator, w: *Io.Writer) (Allocator.Error || Io.Writer.Error)!void {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const keys = try gpa.alloc([]const u8, store.map.count());
    defer gpa.free(keys);
    var it = store.map.keyIterator();
    for (keys) |*slot| slot.* = it.next().?.*;
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);

    var json: std.json.Stringify = .{ .writer = w };
    try json.beginArray();
    for (keys) |key| try json.write(key);
    try json.endArray();
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put get remove" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "a", try gpa.dupe(u8, "2")));

    const value = (try store.get(io, gpa, "a")).?;
    defer gpa.free(value);
    try std.testing.expectEqualStrings("2", value);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
    try std.testing.expectEqual(null, try store.get(io, gpa, "a"));
}

test "keys are listed sorted" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "a-1" }) |key| {
        _ = try store.put(io, key, try gpa.dupe(u8, "x"));
    }

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try store.writeKeysJson(io, gpa, &out.writer);
    try std.testing.expectEqualStrings("[\"C\",\"_\",\"a\",\"a-1\",\"b\"]", out.written());
}
