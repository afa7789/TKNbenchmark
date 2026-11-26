//! A fixed-size pool of SQLite connections to one database file.
//!
//! Connections are opened in multi-thread mode, so each one must be used by a
//! single task at a time; `acquire` hands out exclusive access and blocks while
//! every connection is in use. The database runs in WAL mode so readers do not
//! block the (single) writer.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");
const schema = @import("schema.zig");

const Pool = @This();

gpa: Allocator,
all: []sqlite.Conn,
/// Stack of connections not currently handed out. Guarded by `mutex`.
idle: []sqlite.Conn,
idle_len: usize,
mutex: Io.Mutex = .init,
available: Io.Condition = .init,

pub const Options = struct {
    size: usize = 8,
    /// How long a connection waits for a lock held by another connection.
    busy_timeout_ms: u31 = 5000,
};

/// Opens `options.size` connections to `path`, creating the database file and
/// applying the schema if needed.
pub fn init(gpa: Allocator, path: [:0]const u8, options: Options) !Pool {
    std.debug.assert(options.size > 0);

    const all = try gpa.alloc(sqlite.Conn, options.size);
    errdefer gpa.free(all);
    const idle = try gpa.alloc(sqlite.Conn, options.size);
    errdefer gpa.free(idle);

    var opened: usize = 0;
    errdefer for (all[0..opened]) |conn| conn.close();

    while (opened < all.len) : (opened += 1) {
        const conn = try sqlite.Conn.open(path, .{});
        errdefer conn.close();
        try conn.busyTimeout(options.busy_timeout_ms);
        if (opened == 0) {
            // Persistent database settings and migrations: once, before any
            // other connection uses the file.
            try conn.execScript("PRAGMA journal_mode = WAL");
            try schema.migrate(conn);
        }
        try conn.execScript("PRAGMA foreign_keys = ON");
        all[opened] = conn;
    }

    @memcpy(idle, all);
    return .{ .gpa = gpa, .all = all, .idle = idle, .idle_len = idle.len };
}

/// Closes every connection. All connections must have been released.
pub fn deinit(pool: *Pool) void {
    std.debug.assert(pool.idle_len == pool.all.len);
    for (pool.all) |conn| conn.close();
    pool.gpa.free(pool.all);
    pool.gpa.free(pool.idle);
    pool.* = undefined;
}

/// Takes exclusive use of a connection, waiting until one is free. Return it
/// with `release`.
pub fn acquire(pool: *Pool, io: Io) Io.Cancelable!sqlite.Conn {
    try pool.mutex.lock(io);
    defer pool.mutex.unlock(io);
    while (pool.idle_len == 0) try pool.available.wait(io, &pool.mutex);
    pool.idle_len -= 1;
    return pool.idle[pool.idle_len];
}

pub fn release(pool: *Pool, io: Io, conn: sqlite.Conn) void {
    // A connection must never be returned in the middle of a transaction.
    conn.rollback();
    pool.mutex.lockUncancelable(io);
    defer pool.mutex.unlock(io);
    std.debug.assert(pool.idle_len < pool.idle.len);
    pool.idle[pool.idle_len] = conn;
    pool.idle_len += 1;
    pool.available.signal(io);
}

test "acquire and release" {
    const io = std.testing.io;
    var pool = try Pool.init(std.testing.allocator, ":memory:", .{ .size = 2 });
    defer pool.deinit();

    const a = try pool.acquire(io);
    const b = try pool.acquire(io);
    try std.testing.expect(a.handle != b.handle);
    try std.testing.expectEqual(0, pool.idle_len);
    pool.release(io, a);
    pool.release(io, b);
    try std.testing.expectEqual(2, pool.idle_len);
}
