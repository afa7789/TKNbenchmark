//! Thread-safe in-memory key-value store.
//!
//! Keys and values are owned by the store and allocated with `gpa`. Readers
//! receive copies so the lock is never held while data is being sent to a
//! (possibly slow) client.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
lock: Io.RwLock = .init,
entries: std.StringHashMapUnmanaged([]u8) = .empty,

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(store: *Store) void {
    var it = store.entries.iterator();
    while (it.next()) |entry| {
        store.gpa.free(entry.key_ptr.*);
        store.gpa.free(entry.value_ptr.*);
    }
    store.entries.deinit(store.gpa);
    store.* = undefined;
}

pub const PutResult = enum { created, replaced };

/// Stores `value` under `key`, replacing any previous value.
///
/// `value` must be allocated with the store's `gpa`; on success the store
/// takes ownership of it. On error the caller still owns it.
pub fn put(store: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    try store.lock.lock(io);
    defer store.lock.unlock(io);

    const gop = try store.entries.getOrPut(store.gpa, key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
        store.entries.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value;
    return .created;
}

/// Returns a copy of the value stored under `key`, owned by the caller and
/// allocated with `allocator`, or `null` if the key is absent.
pub fn get(store: *Store, io: Io, allocator: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try store.lock.lockShared(io);
    defer store.lock.unlockShared(io);

    const value = store.entries.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`. Returns whether it was present.
pub fn delete(store: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try store.lock.lock(io);
    defer store.lock.unlock(io);

    const kv = store.entries.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Renders every key, sorted ascending, as a JSON array of strings.
/// The result is owned by the caller and allocated with `allocator`.
///
/// Keys are restricted to `[A-Za-z0-9_-]`, so no JSON escaping is required.
pub fn keysJson(store: *Store, io: Io, allocator: Allocator) (Allocator.Error || Io.Cancelable)![]u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    var json: std.ArrayList(u8) = .empty;
    errdefer json.deinit(allocator);

    {
        try store.lock.lockShared(io);
        defer store.lock.unlockShared(io);

        try keys.ensureTotalCapacityPrecise(allocator, store.entries.count());
        var len: usize = 2; // "[" and "]"
        var it = store.entries.keyIterator();
        while (it.next()) |key| {
            keys.appendAssumeCapacity(key.*);
            len += key.len + 3; // quotes and comma
        }
        std.mem.sortUnstable([]const u8, keys.items, {}, lessThan);

        // Rendered while still holding the lock: the key slices are owned by the map.
        try json.ensureTotalCapacityPrecise(allocator, len);
        json.appendAssumeCapacity('[');
        for (keys.items, 0..) |key, i| {
            if (i != 0) json.appendAssumeCapacity(',');
            json.appendAssumeCapacity('"');
            json.appendSliceAssumeCapacity(key);
            json.appendAssumeCapacity('"');
        }
        json.appendAssumeCapacity(']');
    }

    return json.toOwnedSlice(allocator);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

fn putCopy(store: *Store, key: []const u8, value: []const u8) !PutResult {
    const owned = try store.gpa.dupe(u8, value);
    errdefer store.gpa.free(owned);
    return store.put(testing.io, key, owned);
}

test "put, get, replace, delete" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expectEqual(.created, try putCopy(&store, "a", "hello"));
    {
        const value = (try store.get(io, testing.allocator, "a")).?;
        defer testing.allocator.free(value);
        try testing.expectEqualStrings("hello", value);
    }
    try testing.expectEqual(.replaced, try putCopy(&store, "a", "world"));
    {
        const value = (try store.get(io, testing.allocator, "a")).?;
        defer testing.allocator.free(value);
        try testing.expectEqualStrings("world", value);
    }
    try testing.expect(try store.delete(io, "a"));
    try testing.expect(!try store.delete(io, "a"));
    try testing.expectEqual(null, try store.get(io, testing.allocator, "a"));
}

test "empty values are stored" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expectEqual(.created, try putCopy(&store, "k", ""));
    const value = (try store.get(io, testing.allocator, "k")).?;
    defer testing.allocator.free(value);
    try testing.expectEqual(0, value.len);
}

test "keysJson sorts ascending" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    {
        const json = try store.keysJson(io, testing.allocator);
        defer testing.allocator.free(json);
        try testing.expectEqualStrings("[]", json);
    }
    for ([_][]const u8{ "b", "a", "_", "Z", "c-1", "c" }) |key| _ = try putCopy(&store, key, "v");
    const json = try store.keysJson(io, testing.allocator);
    defer testing.allocator.free(json);
    try testing.expectEqualStrings("[\"Z\",\"_\",\"a\",\"b\",\"c\",\"c-1\"]", json);
}
