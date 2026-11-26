//! Data access for replacing and deleting single notes.

const std = @import("std");
const sqlite = @import("../db/sqlite.zig");
const note = @import("../note.zig");
const notes = @import("notes.zig");
const Note = note.Note;

/// Replaces the title, body and tags of the note with the given id in one
/// transaction. Returns the updated note, or `null` if there is none.
pub fn update(conn: sqlite.Conn, id: i64, input: note.Input) !?Note {
    try conn.begin(.immediate);
    errdefer conn.rollback();

    try conn.exec("UPDATE notes SET title = ?, body = ? WHERE id = ?", .{ input.title, input.body, id });
    if (conn.changes() == 0) {
        conn.rollback();
        return null;
    }
    try conn.exec("DELETE FROM note_tags WHERE note_id = ?", .{id});
    try notes.insertTags(conn, id, input.tags);
    try conn.commit();

    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// Deletes the note with the given id and its tags. Returns `false` if there
/// was no such note.
pub fn delete(conn: sqlite.Conn, id: i64) !bool {
    // Tags go with the note through `ON DELETE CASCADE`.
    try conn.exec("DELETE FROM notes WHERE id = ?", .{id});
    return conn.changes() > 0;
}

const testing = std.testing;

fn tagCount(conn: sqlite.Conn) !i64 {
    var stmt = try conn.prepare("SELECT count(*) FROM note_tags");
    defer stmt.finalize();
    _ = try stmt.step();
    return stmt.columnInt(0);
}

test "update replaces every field" {
    const conn = try notes.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const created = try notes.create(conn, .{ .title = "old", .body = "text", .tags = &.{ "a", "x" } });
    const updated = (try update(conn, created.id, .{ .title = "new", .tags = &.{ "a", "b" } })).?;
    try testing.expectEqual(created.id, updated.id);

    const loaded = (try notes.get(conn, arena.allocator(), created.id)).?;
    try testing.expectEqualStrings("new", loaded.title);
    try testing.expectEqualStrings("", loaded.body);
    try testing.expectEqual(2, loaded.tags.len);
    try testing.expectEqualStrings("a", loaded.tags[0]);
    try testing.expectEqualStrings("b", loaded.tags[1]);

    _ = (try update(conn, created.id, .{ .title = "bare" })).?;
    try testing.expectEqual(0, try tagCount(conn));
}

test "update of a missing note changes nothing" {
    const conn = try notes.openTestDb();
    defer conn.close();

    try testing.expectEqual(null, try update(conn, 1, .{ .title = "none", .tags = &.{"t"} }));
    try testing.expectEqual(0, try tagCount(conn));
}

test "delete removes the note and its tags" {
    const conn = try notes.openTestDb();
    defer conn.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const a = try notes.create(conn, .{ .title = "a", .tags = &.{ "t", "u" } });
    const b = try notes.create(conn, .{ .title = "b", .tags = &.{"t"} });

    try testing.expect(try delete(conn, a.id));
    try testing.expect(!try delete(conn, a.id));
    try testing.expectEqual(null, try notes.get(conn, arena.allocator(), a.id));
    try testing.expect((try notes.get(conn, arena.allocator(), b.id)) != null);
    try testing.expectEqual(1, try tagCount(conn));
}
