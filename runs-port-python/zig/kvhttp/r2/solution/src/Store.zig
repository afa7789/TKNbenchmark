//! Thread-safe in-memory key-value store. Keys and values are owned by the store.

const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

gpa: Allocator,
mutex: Io.Mutex = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *Store) void {
    var it = self.map.iterator();
    while (it.next()) |entry| {
        self.gpa.free(entry.key_ptr.*);
        self.gpa.free(entry.value_ptr.*);
    }
    self.map.deinit(self.gpa);
    self.* = undefined;
}

/// Stores `value`, taking ownership of it (it must have been allocated with
/// the store's allocator). Returns true if the key was new.
pub fn put(self: *Store, io: Io, key: []const u8, value: []u8) Allocator.Error!bool {
    // Allocate the key copy before taking the lock to keep the critical section short.
    const owned_key = try self.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) self.gpa.free(owned_key);

    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);

    const gop = self.map.getOrPut(self.gpa, key) catch |err| {
        self.gpa.free(value);
        return err;
    };
    if (gop.found_existing) {
        self.gpa.free(gop.value_ptr.*);
    } else {
        gop.key_ptr.* = owned_key;
        key_used = true;
    }
    gop.value_ptr.* = value;
    return !gop.found_existing;
}

/// Returns a copy of the value for `key`, allocated with `gpa`, or null if absent.
pub fn getCopy(self: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);

    const value = self.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`. Returns true if it was present.
pub fn delete(self: *Store, io: Io, key: []const u8) bool {
    const removed = blk: {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        break :blk self.map.fetchRemove(key);
    } orelse return false;
    self.gpa.free(removed.key);
    self.gpa.free(removed.value);
    return true;
}

/// Returns every key sorted ascending, serialized as a compact JSON array.
/// Keys are restricted to `[A-Za-z0-9_-]`, so no escaping is required.
pub fn keysJson(self: *Store, io: Io, gpa: Allocator) Allocator.Error![]u8 {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const keys = blk: {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        const keys = try arena.alloc([]const u8, self.map.count());
        var it = self.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |k| : (i += 1) keys[i] = try arena.dupe(u8, k.*);
        break :blk keys;
    };

    std.mem.sortUnstable([]const u8, keys, {}, lessThan);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, '[');
    for (keys, 0..) |k, i| {
        if (i != 0) try out.append(gpa, ',');
        try out.append(gpa, '"');
        try out.appendSlice(gpa, k);
        try out.append(gpa, '"');
    }
    try out.append(gpa, ']');
    return out.toOwnedSlice(gpa);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test "put, get, delete, list" {
    const io = testing.io;
    const gpa = testing.allocator;
    var store: Store = .init(gpa);
    defer store.deinit();

    try testing.expect(try store.put(io, "b", try gpa.dupe(u8, "2")));
    try testing.expect(try store.put(io, "a", try gpa.dupe(u8, "1")));
    try testing.expect(!try store.put(io, "b", try gpa.dupe(u8, "two")));

    const v = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try testing.expectEqualStrings("two", v);
    try testing.expect(try store.getCopy(io, gpa, "zz") == null);

    const json = try store.keysJson(io, gpa);
    defer gpa.free(json);
    try testing.expectEqualStrings("[\"a\",\"b\"]", json);

    try testing.expect(store.delete(io, "a"));
    try testing.expect(!store.delete(io, "a"));
}

test "empty list" {
    var store: Store = .init(testing.allocator);
    defer store.deinit();
    const json = try store.keysJson(testing.io, testing.allocator);
    defer testing.allocator.free(json);
    try testing.expectEqualStrings("[]", json);
}
