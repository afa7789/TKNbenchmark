//! The application's database: a single SQLite connection shared by all
//! request handlers, serialized with a mutex.
//!
//! Usage from a handler:
//!
//!     const db = store.acquire();
//!     defer store.release();
//!     // ... queries on `db` ...

const Store = @This();

const std = @import("std");
const Io = std.Io;
const sqlite = @import("sqlite.zig");
const schema = @import("schema.zig");

io: Io,
db: sqlite.Db,
mutex: Io.Mutex = .init,

/// Opens the database at `path`, creating the file and the schema if needed.
pub fn open(io: Io, path: [:0]const u8) sqlite.Error!Store {
    const db = try sqlite.Db.open(path, .{});
    errdefer db.close();
    try db.exec(
        \\PRAGMA journal_mode = WAL;
        \\PRAGMA synchronous = NORMAL;
        \\PRAGMA foreign_keys = ON;
    );
    try schema.migrate(db);
    return .{ .io = io, .db = db };
}

pub fn close(store: *Store) void {
    store.db.close();
    store.* = undefined;
}

/// Gives the calling task exclusive use of the connection until `release`.
pub fn acquire(store: *Store) sqlite.Db {
    store.mutex.lockUncancelable(store.io);
    return store.db;
}

pub fn release(store: *Store) void {
    store.mutex.unlock(store.io);
}

test "open an in-memory store" {
    var store = try Store.open(std.testing.io, ":memory:");
    defer store.close();
    const db = store.acquire();
    defer store.release();
    try db.run("INSERT INTO notes (title) VALUES (?)", .{"t"});
}
