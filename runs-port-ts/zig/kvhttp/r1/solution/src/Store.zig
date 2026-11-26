//! Thread-safe in-memory key-value store. Keys and values are owned copies of
//! raw bytes; every accessor that hands data back to the caller returns a
//! fresh allocation so it stays valid after the lock is released.

const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

gpa: Allocator,
lock: Io.RwLock = .init,
entries: std.StringHashMapUnmanaged([]u8) = .empty,

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(s: *Store) void {
    var it = s.entries.iterator();
    while (it.next()) |entry| {
        s.gpa.free(entry.key_ptr.*);
        s.gpa.free(entry.value_ptr.*);
    }
    s.entries.deinit(s.gpa);
    s.* = undefined;
}

pub const PutResult = enum { created, replaced };

/// Stores `value` under `key`, taking ownership of `value` (which must have
/// been allocated with `s.gpa`). The key is copied.
pub fn put(s: *Store, io: Io, key: []const u8, value: []u8) (Allocator.Error || Io.Cancelable)!PutResult {
    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const gop = try s.entries.getOrPut(s.gpa, key);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value;
        return .replaced;
    }
    gop.key_ptr.* = s.gpa.dupe(u8, key) catch |err| {
        s.entries.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value;
    return .created;
}

/// Returns a copy of the value stored under `key`, owned by `gpa`, or null.
pub fn get(s: *Store, io: Io, gpa: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const value = s.entries.get(key) orelse return null;
    return try gpa.dupe(u8, value);
}

/// Removes `key`; returns whether it was present.
pub fn remove(s: *Store, io: Io, key: []const u8) Io.Cancelable!bool {
    try s.lock.lock(io);
    defer s.lock.unlock(io);

    const kv = s.entries.fetchRemove(key) orelse return false;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value);
    return true;
}

/// Writes every key as a JSON array of strings, sorted ascending bytewise.
pub fn writeKeysJson(s: *Store, io: Io, gpa: Allocator, w: *Io.Writer) (Allocator.Error || Io.Cancelable || Io.Writer.Error)!void {
    try s.lock.lockShared(io);
    defer s.lock.unlockShared(io);

    const keys = try gpa.alloc([]const u8, s.entries.count());
    defer gpa.free(keys);
    var it = s.entries.keyIterator();
    for (keys) |*k| k.* = it.next().?.*;
    std.mem.sortUnstable([]const u8, keys, {}, lessThan);

    try std.json.Stringify.value(keys, .{}, w);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test "put, get, remove" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    try testing.expectEqual(.created, try store.put(io, "a", try testing.allocator.dupe(u8, "hello")));
    try testing.expectEqual(.replaced, try store.put(io, "a", try testing.allocator.dupe(u8, "world")));

    const got = (try store.get(io, testing.allocator, "a")).?;
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("world", got);

    try testing.expect(try store.remove(io, "a"));
    try testing.expect(!try store.remove(io, "a"));
    try testing.expectEqual(null, try store.get(io, testing.allocator, "a"));
}

test "keys are sorted JSON" {
    const io = testing.io;
    var store: Store = .init(testing.allocator);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "C", "-" }) |k| {
        _ = try store.put(io, k, try testing.allocator.dupe(u8, ""));
    }
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try store.writeKeysJson(io, testing.allocator, &out.writer);
    try testing.expectEqualStrings("[\"-\",\"C\",\"_\",\"a\",\"b\"]", out.written());
}
