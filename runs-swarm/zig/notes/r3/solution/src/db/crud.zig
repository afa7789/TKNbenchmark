//! Data access for replacing and deleting single notes. Functions take a
//! `sqlite.Db` obtained with `Store.acquire`.

const std = @import("std");
const sqlite = @import("sqlite.zig");
const note = @import("../note.zig");
const notes_db = @import("notes.zig");
const Note = note.Note;

/// Replaces the title, body and tags of note `id` in one transaction.
/// Returns the updated note, or null if there is no note with `id`.
pub fn update(db: sqlite.Db, id: i64, input: note.Input) sqlite.Error!?Note {
    try db.begin();
    errdefer db.rollback();
    try db.run("UPDATE notes SET title = ?, body = ? WHERE id = ?", .{ input.title, input.body, id });
    if (db.changes() == 0) {
        db.rollback();
        return null;
    }
    try db.run("DELETE FROM note_tags WHERE note_id = ?", .{id});
    try notes_db.insertTags(db, id, input.tags);
    try db.commit();
    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// Deletes note `id` and, through the foreign key, its tags. Returns
/// whether the note existed.
pub fn remove(db: sqlite.Db, id: i64) sqlite.Error!bool {
    try db.run("DELETE FROM notes WHERE id = ?", .{id});
    return db.changes() > 0;
}

const testing = std.testing;

fn openTestDb() !sqlite.Db {
    const db = try sqlite.Db.open(":memory:", .{});
    errdefer db.close();
    try db.exec("PRAGMA foreign_keys = ON");
    try @import("schema.zig").migrate(db);
    return db;
}

test "update replaces title, body and tags" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    _ = try notes_db.insert(db, .{ .title = "old", .body = "text", .tags = &.{ "x", "y" } });
    const updated = (try update(db, 1, .{ .title = "new", .tags = &.{ "a", "y" } })).?;
    try testing.expectEqual(@as(i64, 1), updated.id);

    const got = (try notes_db.get(db, arena.allocator(), 1)).?;
    try testing.expectEqualStrings("new", got.title);
    try testing.expectEqualStrings("", got.body);
    try testing.expectEqual(2, got.tags.len);
    try testing.expectEqualStrings("a", got.tags[0]);
    try testing.expectEqualStrings("y", got.tags[1]);

    _ = (try update(db, 1, .{ .title = "bare" })).?;
    try testing.expectEqual(0, (try notes_db.tagsOf(db, arena.allocator(), 1)).len);
}

test "update of a missing note changes nothing" {
    const db = try openTestDb();
    defer db.close();

    try testing.expectEqual(null, try update(db, 1, .{ .title = "t", .tags = &.{"a"} }));
    var stmt = try db.prepare("SELECT count(*) FROM note_tags");
    defer stmt.deinit();
    try testing.expect(try stmt.step());
    try testing.expectEqual(@as(i64, 0), stmt.columnInt(0));
}

test "remove deletes a note once and its id is not reused" {
    const db = try openTestDb();
    defer db.close();

    _ = try notes_db.insert(db, .{ .title = "a", .tags = &.{"x"} });
    try testing.expect(try remove(db, 1));
    try testing.expect(!try notes_db.exists(db, 1));
    try testing.expect(!try remove(db, 1));
    try testing.expect(!try remove(db, 2));

    const next = try notes_db.insert(db, .{ .title = "b" });
    try testing.expectEqual(@as(i64, 2), next.id);
}
