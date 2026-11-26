//! Database schema, versioned with `PRAGMA user_version`.
//!
//! To change the schema, append a migration to `migrations`; never edit one
//! that has shipped. Each migration runs in its own transaction.

const std = @import("std");
const sqlite = @import("sqlite.zig");

const log = std.log.scoped(.schema);

const migrations = [_][:0]const u8{
    // 1: notes and their tags.
    //
    // AUTOINCREMENT guarantees that ids are never reused, even after the note
    // with the highest id is deleted. Tags live in their own table so that
    // filtering by tag and counting tags are index lookups.
    \\CREATE TABLE notes (
    \\    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    title TEXT NOT NULL,
    \\    body  TEXT NOT NULL DEFAULT ''
    \\);
    \\CREATE TABLE note_tags (
    \\    note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
    \\    tag     TEXT    NOT NULL,
    \\    PRIMARY KEY (note_id, tag)
    \\) WITHOUT ROWID;
    \\CREATE INDEX note_tags_by_tag ON note_tags (tag, note_id);
    ,
};

pub const latest_version = migrations.len;

/// Brings the database up to `latest_version`.
pub fn migrate(conn: sqlite.Conn) !void {
    try conn.begin(.immediate);
    errdefer conn.rollback();

    const current = try userVersion(conn);
    if (current > latest_version) {
        log.err("database schema version {d} is newer than this program ({d})", .{ current, latest_version });
        return error.UnsupportedSchemaVersion;
    }
    for (migrations[current..], current + 1..) |sql, version| {
        log.info("applying schema migration {d}", .{version});
        try conn.execScript(sql);
    }
    if (current != latest_version) {
        var buf: [64]u8 = undefined;
        const pragma = std.fmt.bufPrintZ(&buf, "PRAGMA user_version = {d}", .{latest_version}) catch unreachable;
        try conn.execScript(pragma);
    }
    try conn.commit();
}

fn userVersion(conn: sqlite.Conn) !usize {
    var stmt = try conn.prepare("PRAGMA user_version");
    defer stmt.finalize();
    _ = try stmt.step();
    return @intCast(stmt.columnInt(0));
}

test "migrate is idempotent" {
    const conn = try sqlite.Conn.open(":memory:", .{});
    defer conn.close();

    try migrate(conn);
    try migrate(conn);
    try std.testing.expectEqual(latest_version, try userVersion(conn));
}
