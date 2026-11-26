//! Database schema, applied as numbered migrations tracked in
//! `PRAGMA user_version`. Append new migrations; never edit applied ones.

const std = @import("std");
const sqlite = @import("sqlite.zig");

const migrations = [_][:0]const u8{
    // 1: notes and their tags.
    \\CREATE TABLE notes (
    \\    -- AUTOINCREMENT: ids are never reused, also after deleting the newest note.
    \\    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    title TEXT NOT NULL,
    \\    body  TEXT NOT NULL DEFAULT ''
    \\) STRICT;
    \\
    \\CREATE TABLE note_tags (
    \\    note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
    \\    tag     TEXT NOT NULL,
    \\    PRIMARY KEY (note_id, tag)
    \\) STRICT, WITHOUT ROWID;
    \\
    \\CREATE INDEX note_tags_by_tag ON note_tags (tag, note_id);
    ,
};

/// Brings the database schema up to date.
pub fn migrate(db: sqlite.Db) sqlite.Error!void {
    const current = std.math.cast(usize, try version(db)) orelse return error.Sqlite;
    if (current > migrations.len) {
        std.log.err("database schema version {d} is newer than this program ({d})", .{ current, migrations.len });
        return error.Sqlite;
    }
    for (migrations[current..], current + 1..) |sql, next| {
        try db.begin();
        errdefer db.rollback();
        try db.exec(sql);
        var buf: [64]u8 = undefined;
        try db.exec(std.fmt.bufPrintZ(&buf, "PRAGMA user_version = {d}", .{next}) catch unreachable);
        try db.commit();
    }
}

fn version(db: sqlite.Db) sqlite.Error!i64 {
    var stmt = try db.prepare("PRAGMA user_version");
    defer stmt.deinit();
    _ = try stmt.step();
    return stmt.columnInt(0);
}

test "migrate creates the schema and is idempotent" {
    const db = try sqlite.Db.open(":memory:", .{});
    defer db.close();
    try migrate(db);
    try migrate(db);
    try std.testing.expectEqual(@as(i64, migrations.len), try version(db));
    try db.run("INSERT INTO notes (title) VALUES (?)", .{"t"});
}
