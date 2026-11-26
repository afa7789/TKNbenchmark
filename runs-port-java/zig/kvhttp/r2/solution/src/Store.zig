//! Thread-safe in-memory key-value store. Keys and values are owned copies.

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

/// Stores `value` under `key`. Takes ownership of `value`, which must have
/// been allocated with the store's allocator, even when an error is returned.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    errdefer s.gpa.free(value);

    try s.lock.lock(io);
    defer s.lock.unlock(io);

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

/// Returns a copy of the value stored under `key`, allocated with `allocator`.
pub fn get(s: *Store, io: Io, allocator: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const value = s.map.get(key) orelse return null;
    return try allocator.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn delete(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const kv = s.map.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Writes every key, sorted ascending, as a JSON array of strings.
pub fn writeKeysJson(s: *Store, io: Io, scratch: Allocator, w: *Io.Writer) (Allocator.Error || Io.Cancelable || Io.Writer.Error)!void {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const keys = try scratch.alloc([]const u8, s.map.count());
    defer scratch.free(keys);

    var it = s.map.keyIterator();
    var i: usize = 0;
    while (it.next()) |key| : (i += 1) keys[i] = key.*;
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);

    try w.writeByte('[');
    for (keys, 0..) |key, n| {
        if (n != 0) try w.writeByte(',');
        try std.json.Stringify.encodeJsonString(key, .{}, w);
    }
    try w.writeByte(']');
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, replace, delete" {
    const io = std.testing.io;
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "a", try dupe("hello")));
    try std.testing.expectEqual(.replaced, try store.put(io, "a", try dupe("world")));

    const value = (try store.get(io, std.testing.allocator, "a")).?;
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("world", value);

    try std.testing.expect(try store.delete(io, "a"));
    try std.testing.expect(!try store.delete(io, "a"));
    try std.testing.expectEqual(null, try store.get(io, std.testing.allocator, "a"));
}

test "keys are listed in ascending order" {
    const io = std.testing.io;
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "a-1" }) |key| _ = try store.put(io, key, try dupe(""));

    var out: Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try store.writeKeysJson(io, std.testing.allocator, &out.writer);
    try std.testing.expectEqualStrings("[\"C\",\"_\",\"a\",\"a-1\",\"b\"]", out.written());
}

fn dupe(bytes: []const u8) ![]u8 {
    return std.testing.allocator.dupe(u8, bytes);
}
