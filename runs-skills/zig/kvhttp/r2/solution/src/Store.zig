//! Thread-safe in-memory key-value store. Keys and values are owned by the store.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Store = @This();

gpa: Allocator,
mutex: Io.Mutex = .init,
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

/// Stores `value`, taking ownership of it. `value` must have been allocated
/// with the store's allocator. On error, ownership stays with the caller.
pub fn putOwned(s: *Store, io: Io, key: []const u8, value: []u8) Allocator.Error!PutResult {
    // Allocate the key copy outside the critical section.
    const key_copy = try s.gpa.dupe(u8, key);
    var key_used = false;
    defer if (!key_used) s.gpa.free(key_copy);

    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    const gop = try s.map.getOrPut(s.gpa, key);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = key_copy;
    gop.value_ptr.* = value;
    key_used = true;
    return .created;
}

/// Returns a copy of the value for `key`, allocated with `out_gpa`, or null.
pub fn getCopy(s: *Store, io: Io, out_gpa: Allocator, key: []const u8) Allocator.Error!?[]u8 {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);
    const value = s.map.get(key) orelse return null;
    return try out_gpa.dupe(u8, value);
}

/// Removes `key`. Returns whether it was present.
pub fn remove(s: *Store, io: Io, key: []const u8) bool {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);
    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Returns every key, sorted ascending. Keys and the slice are allocated with
/// `out_gpa`; free them with `freeKeys`.
pub fn sortedKeys(s: *Store, io: Io, out_gpa: Allocator) Allocator.Error![][]u8 {
    const keys = blk: {
        s.mutex.lockUncancelable(io);
        defer s.mutex.unlock(io);

        const keys = try out_gpa.alloc([]u8, s.map.count());
        var n: usize = 0;
        errdefer {
            for (keys[0..n]) |k| out_gpa.free(k);
            out_gpa.free(keys);
        }
        var it = s.map.keyIterator();
        while (it.next()) |k| : (n += 1) keys[n] = try out_gpa.dupe(u8, k.*);
        break :blk keys;
    };
    std.mem.sortUnstable([]u8, keys, {}, lessThan);
    return keys;
}

pub fn freeKeys(out_gpa: Allocator, keys: [][]u8) void {
    for (keys) |k| out_gpa.free(k);
    out_gpa.free(keys);
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove, list" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: Store = .init(gpa);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.putOwned(io, "b", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(.replaced, try store.putOwned(io, "b", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(.created, try store.putOwned(io, "a", try gpa.dupe(u8, "")));

    const v = (try store.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("2", v);
    try std.testing.expectEqual(null, try store.getCopy(io, gpa, "zz"));

    const keys = try store.sortedKeys(io, gpa);
    defer freeKeys(gpa, keys);
    try std.testing.expectEqual(2, keys.len);
    try std.testing.expectEqualStrings("a", keys[0]);
    try std.testing.expectEqualStrings("b", keys[1]);

    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
}
