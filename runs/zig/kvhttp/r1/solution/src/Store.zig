//! Thread-safe in-memory key-value store. Keys and values are owned by the
//! store and allocated with its allocator.

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
/// the store's allocator). `key` is copied.
pub fn put(store: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    errdefer store.gpa.free(value);
    // Allocate outside the critical section; freed below if the key exists.
    const owned_key = try store.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) store.gpa.free(owned_key);

    try store.lock.lock(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, owned_key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    key_used = true;
    gop.value_ptr.* = value;
    return .created;
}

/// Returns a copy of the value for `key`, owned by the caller and allocated
/// with `gpa`, or null if the key is absent.
pub fn getCopy(store: *Store, io: Io, gpa: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try store.lock.lockShared(io);
    defer store.lock.unlockShared(io);
    const value = store.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Returns whether the key was present.
pub fn delete(store: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try store.lock.lock(io);
    defer store.lock.unlock(io);
    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Writes every key, sorted ascending, as a JSON array of strings.
pub fn writeKeysJson(store: *Store, io: Io, gpa: Allocator, w: *Io.Writer) (Allocator.Error || Io.Writer.Error || Io.Cancelable)!void {
    try store.lock.lockShared(io);
    defer store.lock.unlockShared(io);

    const keys = try gpa.alloc([]const u8, store.map.count());
    defer gpa.free(keys);
    var it = store.map.keyIterator();
    var i: usize = 0;
    while (it.next()) |k| : (i += 1) keys[i] = k.*;

    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    try std.json.Stringify.value(keys, .{}, w);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, get, delete, list" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "b", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.put(io, "a", try gpa.dupe(u8, "")));

    const v = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("2", v);
    try std.testing.expectEqual(null, try store.getCopy(io, gpa, "zz"));

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try store.writeKeysJson(io, gpa, &out.writer);
    try std.testing.expectEqualStrings("[\"a\",\"b\"]", out.written());

    try std.testing.expect(try store.delete(io, "a"));
    try std.testing.expect(!try store.delete(io, "a"));
}
