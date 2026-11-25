//! Thread-safe in-memory key-value store. Keys and values are owned copies.
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
    while (it.next()) |e| {
        s.gpa.free(e.key_ptr.*);
        s.gpa.free(e.value_ptr.*);
    }
    s.map.deinit(s.gpa);
    s.* = undefined;
}

/// Stores `value` under `key`. Takes ownership of `value`, which must have
/// been allocated with the store's allocator.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    try s.mutex.lock(io);
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
pub fn getCopy(s: *Store, io: Io, gpa: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);
    const value = s.map.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Returns true if the key existed.
pub fn remove(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);
    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Writes every key, sorted ascending, as a JSON array of strings.
pub fn writeKeysJson(s: *Store, io: Io, gpa: Allocator, w: *Io.Writer) (Allocator.Error || Io.Cancelable || Io.Writer.Error)!void {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);

    const keys = try gpa.alloc([]const u8, s.map.count());
    defer gpa.free(keys);
    var it = s.map.keyIterator();
    var i: usize = 0;
    while (it.next()) |k| : (i += 1) keys[i] = k.*;

    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    try std.json.Stringify.value(keys, .{}, w);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, remove, list" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var s: Store = .init(gpa);
    defer s.deinit();

    try std.testing.expectEqual(PutResult.created, try s.put(io, "b", try gpa.dupe(u8, "1")));
    try std.testing.expectEqual(PutResult.created, try s.put(io, "a", try gpa.dupe(u8, "2")));
    try std.testing.expectEqual(PutResult.replaced, try s.put(io, "b", try gpa.dupe(u8, "3")));

    const v = (try s.getCopy(io, gpa, "b")).?;
    defer gpa.free(v);
    try std.testing.expectEqualStrings("3", v);

    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try s.writeKeysJson(io, gpa, &aw.writer);
    try std.testing.expectEqualStrings("[\"a\",\"b\"]", aw.written());

    try std.testing.expect(try s.remove(io, "a"));
    try std.testing.expect(!try s.remove(io, "a"));
    try std.testing.expectEqual(null, try s.getCopy(io, gpa, "a"));
}
