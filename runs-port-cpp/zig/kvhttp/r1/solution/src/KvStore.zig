//! Thread-safe in-memory key/value store.
//!
//! Values are reference counted so readers can drop the lock before a
//! (possibly large) value is written to the network.

const KvStore = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

gpa: Allocator,
lock: Io.RwLock = .init,
map: std.StringHashMapUnmanaged(*Value) = .empty,

/// An immutable, reference-counted stored value.
pub const Value = struct {
    refs: std.atomic.Value(u32),
    bytes: []const u8,

    /// Takes ownership of `bytes` on success.
    fn create(gpa: Allocator, bytes: []const u8) Allocator.Error!*Value {
        const value = try gpa.create(Value);
        value.* = .{ .refs = .init(1), .bytes = bytes };
        return value;
    }

    pub fn retain(value: *Value) void {
        _ = value.refs.fetchAdd(1, .monotonic);
    }

    /// Drops one reference, freeing the value when it was the last one.
    pub fn release(value: *Value, gpa: Allocator) void {
        if (value.refs.fetchSub(1, .acq_rel) != 1) return;
        gpa.free(value.bytes);
        gpa.destroy(value);
    }
};

pub fn init(gpa: Allocator) KvStore {
    return .{ .gpa = gpa };
}

pub fn deinit(store: *KvStore) void {
    var it = store.map.iterator();
    while (it.next()) |entry| {
        store.gpa.free(entry.key_ptr.*);
        entry.value_ptr.*.release(store.gpa);
    }
    store.map.deinit(store.gpa);
    store.* = undefined;
}

/// Stores `bytes` under `key`. `bytes` must be allocated with the store's
/// allocator; ownership passes to the store on success and stays with the
/// caller on error. Returns true if the key was new, false if it replaced a
/// value.
pub fn put(store: *KvStore, io: Io, key: []const u8, bytes: []const u8) Allocator.Error!bool {
    const value = try Value.create(store.gpa, bytes);
    errdefer store.gpa.destroy(value);

    const replaced: ?*Value = replaced: {
        store.lock.lockUncancelable(io);
        defer store.lock.unlock(io);

        const gop = try store.map.getOrPut(store.gpa, key);
        if (gop.found_existing) {
            const old = gop.value_ptr.*;
            gop.value_ptr.* = value;
            break :replaced old;
        }
        gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
            store.map.removeByPtr(gop.key_ptr);
            return err;
        };
        gop.value_ptr.* = value;
        break :replaced null;
    };

    // Free the old value outside the critical section.
    if (replaced) |old| old.release(store.gpa);
    return replaced == null;
}

/// Returns the value stored under `key`, or null. The caller owns one
/// reference and must call `Value.release`.
pub fn get(store: *KvStore, io: Io, key: []const u8) ?*Value {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);

    const value = store.map.get(key) orelse return null;
    value.retain();
    return value;
}

/// Removes `key`. Returns true if it was present.
pub fn remove(store: *KvStore, io: Io, key: []const u8) bool {
    const removed = removed: {
        store.lock.lockUncancelable(io);
        defer store.lock.unlock(io);
        break :removed store.map.fetchRemove(key) orelse return false;
    };
    store.gpa.free(removed.key);
    removed.value.release(store.gpa);
    return true;
}

/// Returns a copy of every key in ascending byte-wise order. All memory is
/// allocated with `arena`; the caller frees it by resetting the arena.
pub fn sortedKeys(store: *KvStore, io: Io, arena: Allocator) Allocator.Error![]const []const u8 {
    const keys = keys: {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);

        const keys = try arena.alloc([]const u8, store.map.count());
        var it = store.map.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| : (i += 1) keys[i] = try arena.dupe(u8, key.*);
        break :keys keys;
    };

    std.mem.sortUnstable([]const u8, keys, {}, lessThan);
    return keys;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "put, get, replace, remove" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: KvStore = .init(gpa);
    defer store.deinit();

    try std.testing.expect(try store.put(io, "a", try gpa.dupe(u8, "one")));
    try std.testing.expect(!try store.put(io, "a", try gpa.dupe(u8, "two")));

    const value = store.get(io, "a").?;
    defer value.release(gpa);
    try std.testing.expectEqualStrings("two", value.bytes);

    // A reader's reference outlives removal.
    try std.testing.expect(store.remove(io, "a"));
    try std.testing.expect(!store.remove(io, "a"));
    try std.testing.expect(store.get(io, "a") == null);
    try std.testing.expectEqualStrings("two", value.bytes);
}

test "sortedKeys" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var store: KvStore = .init(gpa);
    defer store.deinit();

    for ([_][]const u8{ "b", "a", "_", "B", "c" }) |key| {
        _ = try store.put(io, key, try gpa.dupe(u8, key));
    }

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const keys = try store.sortedKeys(io, arena.allocator());
    const expected = [_][]const u8{ "B", "_", "a", "b", "c" };
    try std.testing.expectEqual(expected.len, keys.len);
    for (expected, keys) |want, got| try std.testing.expectEqualStrings(want, got);
}
