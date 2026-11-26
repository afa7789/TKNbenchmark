//! Thread-safe in-memory key-value store.
//!
//! Values are immutable, reference-counted `Blob`s: readers take a reference
//! under the lock and release it after transmitting, so the lock is never
//! held during network I/O.
const Store = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

gpa: Allocator,
lock: Io.RwLock = .init,
map: std.StringHashMapUnmanaged(*Blob) = .empty,

pub const key_max = 64;

pub const Blob = struct {
    refs: std.atomic.Value(usize),
    data: []const u8,

    fn create(gpa: Allocator, bytes: []const u8) Allocator.Error!*Blob {
        const blob = try gpa.create(Blob);
        errdefer gpa.destroy(blob);
        blob.* = .{ .refs = .init(1), .data = try gpa.dupe(u8, bytes) };
        return blob;
    }

    fn retain(blob: *Blob) void {
        _ = blob.refs.fetchAdd(1, .monotonic);
    }
};

pub const PutResult = enum { created, replaced };

pub fn init(gpa: Allocator) Store {
    return .{ .gpa = gpa };
}

pub fn deinit(store: *Store) void {
    var it = store.map.iterator();
    while (it.next()) |entry| {
        store.gpa.free(entry.key_ptr.*);
        store.release(entry.value_ptr.*);
    }
    store.map.deinit(store.gpa);
    store.* = undefined;
}

/// Drops a reference obtained from `get`.
pub fn release(store: *Store, blob: *Blob) void {
    if (blob.refs.fetchSub(1, .acq_rel) == 1) {
        store.gpa.free(blob.data);
        store.gpa.destroy(blob);
    }
}

/// Stores a copy of `value` under a copy of `key`.
pub fn put(store: *Store, io: Io, key: []const u8, value: []const u8) Allocator.Error!PutResult {
    const blob = try Blob.create(store.gpa, value);
    errdefer store.release(blob);

    store.lock.lockUncancelable(io);
    const gop = gop: {
        errdefer store.lock.unlock(io);
        const gop = try store.map.getOrPut(store.gpa, key);
        if (!gop.found_existing) {
            gop.key_ptr.* = store.gpa.dupe(u8, key) catch |err| {
                store.map.removeByPtr(gop.key_ptr);
                return err;
            };
        }
        break :gop gop;
    };
    const old = if (gop.found_existing) gop.value_ptr.* else null;
    gop.value_ptr.* = blob;
    store.lock.unlock(io);

    if (old) |b| {
        store.release(b);
        return .replaced;
    }
    return .created;
}

/// Returns a new reference to the value (drop it with `release`), or null.
pub fn get(store: *Store, io: Io, key: []const u8) ?*Blob {
    store.lock.lockSharedUncancelable(io);
    defer store.lock.unlockShared(io);
    const blob = store.map.get(key) orelse return null;
    blob.retain();
    return blob;
}

/// Returns true if the key existed and was removed.
pub fn delete(store: *Store, io: Io, key: []const u8) bool {
    store.lock.lockUncancelable(io);
    const removed = store.map.fetchRemove(key);
    store.lock.unlock(io);

    const kv = removed orelse return false;
    store.gpa.free(kv.key);
    store.release(kv.value);
    return true;
}

/// Returns every key, sorted ascending by byte value. All memory, including
/// the key strings, is owned by `arena`.
pub fn keys(store: *Store, io: Io, arena: Allocator) Allocator.Error![]const []const u8 {
    const list = list: {
        store.lock.lockSharedUncancelable(io);
        defer store.lock.unlockShared(io);
        const list = try arena.alloc([]const u8, store.map.count());
        var it = store.map.keyIterator();
        for (list) |*slot| slot.* = try arena.dupe(u8, it.next().?.*);
        break :list list;
    };
    std.mem.sort([]const u8, list, {}, lessThan);
    return list;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "put, get, replace, delete" {
    const io = std.testing.io;
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();

    try std.testing.expectEqual(.created, try store.put(io, "a", "hello"));
    try std.testing.expectEqual(.replaced, try store.put(io, "a", "world"));

    const blob = store.get(io, "a").?;
    defer store.release(blob);
    try std.testing.expectEqualStrings("world", blob.data);

    try std.testing.expect(store.delete(io, "a"));
    try std.testing.expect(!store.delete(io, "a"));
    try std.testing.expectEqual(null, store.get(io, "a"));
    // The reference taken before deletion stays valid.
    try std.testing.expectEqualStrings("world", blob.data);
}

test "keys are sorted" {
    const io = std.testing.io;
    var store: Store = .init(std.testing.allocator);
    defer store.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    for ([_][]const u8{ "b", "a", "_", "B", "c-1" }) |k| _ = try store.put(io, k, "");
    const list = try store.keys(io, arena.allocator());
    try std.testing.expectEqual(5, list.len);
    const want = [_][]const u8{ "B", "_", "a", "b", "c-1" };
    for (want, list) |w, got| try std.testing.expectEqualStrings(w, got);
}
