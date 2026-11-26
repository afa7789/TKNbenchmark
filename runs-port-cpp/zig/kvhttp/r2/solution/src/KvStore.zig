//! Thread-safe in-memory key-value store. Owns copies of all keys and values.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const KvStore = @This();

gpa: Allocator,
lock: Io.RwLock = .init,
map: std.StringHashMapUnmanaged([]u8) = .empty,

pub const PutResult = enum { created, replaced };

pub fn init(gpa: Allocator) KvStore {
    return .{ .gpa = gpa };
}

pub fn deinit(store: *KvStore) void {
    var it = store.map.iterator();
    while (it.next()) |entry| {
        store.gpa.free(entry.key_ptr.*);
        store.gpa.free(entry.value_ptr.*);
    }
    store.map.deinit(store.gpa);
    store.* = undefined;
}

pub fn put(store: *KvStore, io: Io, key: []const u8, value: []const u8) (Allocator.Error || Io.Cancelable)!PutResult {
    const value_copy = try store.gpa.dupe(u8, value);
    errdefer store.gpa.free(value_copy);

    try store.lock.lock(io);
    defer store.lock.unlock(io);

    const gop = try store.map.getOrPut(store.gpa, key);
    if (gop.found_existing) {
        store.gpa.free(gop.value_ptr.*);
        gop.value_ptr.* = value_copy;
        return .replaced;
    }
    gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
        store.map.removeByPtr(gop.key_ptr);
        return err;
    };
    gop.value_ptr.* = value_copy;
    return .created;
}

/// Returns a copy of the value owned by `arena`, or null if absent.
pub fn get(store: *KvStore, io: Io, arena: Allocator, key: []const u8) (Allocator.Error || Io.Cancelable)!?[]u8 {
    try store.lock.lockShared(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    return try arena.dupe(u8, value);
}

pub fn remove(store: *KvStore, io: Io, key: []const u8) Io.Cancelable!bool {
    try store.lock.lock(io);
    defer store.lock.unlock(io);

    const kv = store.map.fetchRemove(key) orelse return false;
    store.gpa.free(kv.key);
    store.gpa.free(kv.value);
    return true;
}

/// Returns copies of every key, sorted ascending, owned by `arena`.
pub fn keys(store: *KvStore, io: Io, arena: Allocator) (Allocator.Error || Io.Cancelable)![][]const u8 {
    const out = blk: {
        try store.lock.lockShared(io);
        defer store.lock.unlockShared(io);

        const out = try arena.alloc([]const u8, store.map.count());
        var it = store.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| : (i += 1) {
            out[i] = try arena.dupe(u8, key.*);
        }
        break :blk out;
    };
    std.mem.sortUnstable([]const u8, out, {}, lessThan);
    return out;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const testing = std.testing;

test KvStore {
    const io = testing.io;
    var store: KvStore = .init(testing.allocator);
    defer store.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try testing.expectEqual(.created, try store.put(io, "b", "1"));
    try testing.expectEqual(.replaced, try store.put(io, "b", "2"));
    try testing.expectEqual(.created, try store.put(io, "a", "3"));
    try testing.expectEqualStrings("2", (try store.get(io, arena, "b")).?);
    try testing.expectEqual(null, try store.get(io, arena, "c"));

    const listed = try store.keys(io, arena);
    try testing.expectEqual(2, listed.len);
    try testing.expectEqualStrings("a", listed[0]);
    try testing.expectEqualStrings("b", listed[1]);

    try testing.expect(try store.remove(io, "a"));
    try testing.expect(!try store.remove(io, "a"));
}
