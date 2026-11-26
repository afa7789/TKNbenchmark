//! The notes database: one SQLite connection shared by all request handlers.
//!
//! Handlers never touch the connection directly; the data-access modules in
//! `src/store/` call `acquire`/`release` around their queries so requests on
//! different threads are serialized.

const std = @import("std");
const sqlite = @import("sqlite.zig");

const Store = @This();

io: std.Io,
db: sqlite.Db,
mutex: std.Io.Mutex = .init,

/// Bumped whenever `migrations` gains an entry.
const schema_version = migrations.len;

/// Applied in order; entry `i` upgrades a database from version `i` to `i + 1`.
const migrations = [_][:0]const u8{
    \\CREATE TABLE notes (
    \\    -- AUTOINCREMENT: ids are never reused, also after deleting the newest note.
    \\    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    title TEXT NOT NULL,
    \\    body  TEXT NOT NULL DEFAULT ''
    \\);
    \\CREATE TABLE note_tags (
    \\    note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
    \\    tag     TEXT NOT NULL,
    \\    PRIMARY KEY (note_id, tag)
    \\) WITHOUT ROWID;
    \\CREATE INDEX note_tags_by_tag ON note_tags (tag, note_id);
    ,
};

pub fn open(io: std.Io, path: [:0]const u8) !Store {
    const db = try sqlite.Db.open(path, .{});
    errdefer db.close();
    try db.exec(
        \\PRAGMA journal_mode = WAL;
        \\PRAGMA synchronous = NORMAL;
        \\PRAGMA foreign_keys = ON;
    );
    try migrate(db);
    return .{ .io = io, .db = db };
}

pub fn close(store: *Store) void {
    store.db.close();
    store.* = undefined;
}

/// Exclusive access to the connection until `release`.
pub fn acquire(store: *Store) std.Io.Cancelable!sqlite.Db {
    try store.mutex.lock(store.io);
    return store.db;
}

pub fn release(store: *Store) void {
    store.mutex.unlock(store.io);
}

fn migrate(db: sqlite.Db) !void {
    const current = blk: {
        const stmt = try db.prepare("PRAGMA user_version");
        defer stmt.finalize();
        _ = try stmt.step();
        break :blk stmt.int(0);
    };
    if (current > schema_version) return error.UnsupportedSchemaVersion;

    for (migrations[@intCast(current)..], @intCast(current + 1)..) |sql, version| {
        try db.exec("BEGIN IMMEDIATE");
        errdefer db.exec("ROLLBACK") catch {};
        try db.exec(sql);
        var buf: [64]u8 = undefined;
        try db.exec(try std.fmt.bufPrintZ(&buf, "PRAGMA user_version = {d}", .{version}));
        try db.exec("COMMIT");
    }
}

test "open creates the schema and is idempotent" {
    var store = try Store.open(std.testing.io, ":memory:");
    defer store.close();
    try migrate(store.db);

    const stmt = try store.db.prepare("SELECT count(*) FROM sqlite_schema WHERE name IN ('notes', 'note_tags')");
    defer stmt.finalize();
    try std.testing.expect(try stmt.step());
    try std.testing.expectEqual(@as(i64, 2), stmt.int(0));
}
