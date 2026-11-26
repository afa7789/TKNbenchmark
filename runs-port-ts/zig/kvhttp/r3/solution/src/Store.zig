//! Thread-safe in-memory key-value store holding raw byte values.
//!
//! Keys and values are owned by the store and allocated with `gpa`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
mutex: Io.Mutex = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

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
/// been allocated with the store's allocator. Returns true if the key was
/// newly created, false if an existing value was replaced.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!bool {
    // Duplicate the key before locking so the critical section stays short.
    // It is freed again if the key turns out to exist already.
    const owned_key = try s.gpa.dupe(u8, key);
    errdefer s.gpa.free(owned_key);

    const old_value: ?[]u8 = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        const gop = try s.map.getOrPut(s.gpa, owned_key);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = value;
            break :blk old;
        }
        gop.value_ptr.* = value;
        break :blk null;
    };

    if (old_value) |old| {
        s.gpa.free(owned_key);
        s.gpa.free(old);
        return false;
    }
    return true;
}

/// Returns a copy of the value stored under `key`, allocated with `allocator`,
/// or null if the key is absent. The caller owns the returned memory.
pub fn get(s: *Store, io: Io, allocator: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);
    const value = s.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`. Returns true if it was present.
pub fn remove(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    const removed = blk: {
        try s.mutex.lock(io);
        defer s.mutex.unlock(io);
        break :blk s.map.fetchRemove(key) orelse return false;
    };
    s.gpa.free(removed.key);
    s.gpa.free(removed.value);
    return true;
}

/// Returns every key, sorted ascending by byte order, encoded as a JSON array
/// of strings. Keys are restricted to `[A-Za-z0-9_-]`, so no escaping is
/// needed. The caller owns the returned memory.
pub fn keysJson(s: *Store, io: Io, allocator: Allocator) (Allocator.Error || Io.Cancelable)![]u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);
    var json: std.ArrayList(u8) = .empty;
    errdefer json.deinit(allocator);

    try s.mutex.lock(io);
    defer s.mutex.unlock(io);

    try keys.ensureTotalCapacityPrecise(allocator, s.map.count());
    var json_len: usize = 2; // "[" and "]"
    var it = s.map.keyIterator();
    while (it.next()) |key| {
        keys.appendAssumeCapacity(key.*);
        json_len += key.len + 3; // quotes and separator
    }
    std.mem.sortUnstable([]const u8, keys.items, {}, lessThan);

    try json.ensureTotalCapacityPrecise(allocator, json_len);
    json.appendAssumeCapacity('[');
    for (keys.items, 0..) |key, i| {
        if (i != 0) json.appendAssumeCapacity(',');
        json.appendAssumeCapacity('"');
        json.appendSliceAssumeCapacity(key);
        json.appendAssumeCapacity('"');
    }
    json.appendAssumeCapacity(']');
    return json.toOwnedSlice(allocator);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test "put, get, remove" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expect(try store.put(io, "a", try testing.allocator.dupe(u8, "hello")));
    try testing.expect(!try store.put(io, "a", try testing.allocator.dupe(u8, "world")));

    const value = (try store.get(io, testing.allocator, "a")).?;
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("world", value);

    try testing.expect(try store.remove(io, "a"));
    try testing.expect(!try store.remove(io, "a"));
    try testing.expectEqual(null, try store.get(io, testing.allocator, "a"));
}

test "keys are listed sorted" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "-" }) |key| {
        _ = try store.put(io, key, try testing.allocator.dupe(u8, "v"));
    }

    const json = try store.keysJson(io, testing.allocator);
    defer testing.allocator.free(json);
    try testing.expectEqualStrings("[\"-\",\"C\",\"_\",\"a\",\"b\"]", json);
}
