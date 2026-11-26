//! Thread-safe in-memory key-value store. Keys and values are owned by the
//! store and allocated with `gpa`.

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

pub const PutResult = enum { created, replaced };

/// Stores `value` under `key`, taking ownership of `value` (which must have
/// been allocated with the store's allocator) even on error.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) Allocator.Error!PutResult {
    errdefer s.gpa.free(value);

    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

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

/// Returns a copy of the value stored under `key`, owned by the caller.
pub fn getCopy(s: *Store, io: Io, gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Returns whether the key was present.
pub fn remove(s: *Store, io: Io, key: []const u8) bool {
    const kv = kv: {
        s.mutex.lockUncancelable(io);
        defer s.mutex.unlock(io);
        break :kv s.map.fetchRemove(key) orelse return false;
    };
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Serializes every key, sorted ascending by byte value, as a JSON array.
/// The result is owned by the caller.
pub fn keysJson(s: *Store, io: Io, gpa: Allocator) Allocator.Error![]u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(gpa);

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    try keys.ensureTotalCapacityPrecise(gpa, s.map.count());
    var it = s.map.keyIterator();
    while (it.next()) |key| keys.appendAssumeCapacity(key.*);
    std.mem.sortUnstable([]const u8, keys.items, {}, lessThan);

    std.json.Stringify.value(keys.items, .{}, &out.writer) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove, list" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.put(io, "a", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.put(io, "b", try gpa.dupe(u8, "3")));

    const v = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("3", v);
    try std.testing.expectEqual(null, try store.getCopy(io, gpa, "zz"));

    const json = try store.keysJson(io, gpa);
    defer gpa.free(json);
    try std.testing.expectEqualStrings("[\"a\",\"b\"]", json);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
}
