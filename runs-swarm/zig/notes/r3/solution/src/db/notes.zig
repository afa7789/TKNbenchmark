//! Data access for single notes. Functions take a `sqlite.Db` obtained with
//! `Store.acquire` and allocate results in the given (request) arena.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sqlite = @import("sqlite.zig");
const note = @import("../note.zig");
const Note = note.Note;

pub const Error = sqlite.Error || Allocator.Error;

/// Inserts a new note with its tags in one transaction.
pub fn insert(db: sqlite.Db, input: note.Input) sqlite.Error!Note {
    try db.begin();
    errdefer db.rollback();
    try db.run("INSERT INTO notes (title, body) VALUES (?, ?)", .{ input.title, input.body });
    const id = db.lastInsertRowId();
    try insertTags(db, id, input.tags);
    try db.commit();
    return .{ .id = id, .title = input.title, .body = input.body, .tags = input.tags };
}

/// Returns the note with `id`, or null if there is none.
pub fn get(db: sqlite.Db, arena: Allocator, id: i64) Error!?Note {
    var stmt = try db.prepare("SELECT title, body FROM notes WHERE id = ?");
    defer stmt.deinit();
    try stmt.bindAll(.{id});
    if (!try stmt.step()) return null;
    return .{
        .id = id,
        .title = try stmt.columnTextAlloc(arena, 0),
        .body = try stmt.columnTextAlloc(arena, 1),
        .tags = try tagsOf(db, arena, id),
    };
}

/// Whether a note with `id` exists.
pub fn exists(db: sqlite.Db, id: i64) sqlite.Error!bool {
    var stmt = try db.prepare("SELECT 1 FROM notes WHERE id = ?");
    defer stmt.deinit();
    try stmt.bindAll(.{id});
    return stmt.step();
}

/// The tags of note `id`, sorted ascending.
pub fn tagsOf(db: sqlite.Db, arena: Allocator, id: i64) Error![]const []const u8 {
    var stmt = try db.prepare("SELECT tag FROM note_tags WHERE note_id = ? ORDER BY tag");
    defer stmt.deinit();
    try stmt.bindAll(.{id});
    var tags: std.ArrayList([]const u8) = .empty;
    while (try stmt.step()) try tags.append(arena, try stmt.columnTextAlloc(arena, 0));
    return tags.toOwnedSlice(arena);
}

/// Adds `tags` (unique) to note `id`. Call inside a transaction.
pub fn insertTags(db: sqlite.Db, id: i64, tags: []const []const u8) sqlite.Error!void {
    if (tags.len == 0) return;
    var stmt = try db.prepare("INSERT INTO note_tags (note_id, tag) VALUES (?, ?)");
    defer stmt.deinit();
    for (tags) |tag| {
        try stmt.bindAll(.{ id, tag });
        _ = try stmt.step();
        stmt.reset();
    }
}

const testing = std.testing;

fn openTestDb() !sqlite.Db {
    const db = try sqlite.Db.open(":memory:", .{});
    errdefer db.close();
    try db.exec("PRAGMA foreign_keys = ON");
    try @import("schema.zig").migrate(db);
    return db;
}

test "insert assigns increasing ids and get reads notes back" {
    const db = try openTestDb();
    defer db.close();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const first = try insert(db, .{ .title = "first" });
    const second = try insert(db, .{ .title = "second", .body = "text", .tags = &.{ "a", "b-2" } });
    try testing.expectEqual(@as(i64, 1), first.id);
    try testing.expectEqual(@as(i64, 2), second.id);

    const got = (try get(db, arena.allocator(), 2)).?;
    try testing.expectEqualStrings("second", got.title);
    try testing.expectEqualStrings("text", got.body);
    try testing.expectEqual(2, got.tags.len);
    try testing.expectEqualStrings("a", got.tags[0]);
    try testing.expectEqualStrings("b-2", got.tags[1]);

    const empty = (try get(db, arena.allocator(), 1)).?;
    try testing.expectEqual(0, empty.tags.len);

    try testing.expectEqual(null, try get(db, arena.allocator(), 3));
    try testing.expect(try exists(db, 1));
    try testing.expect(!try exists(db, 3));
}

test "deleting a note deletes its tags and its id is not reused" {
    const db = try openTestDb();
    defer db.close();

    _ = try insert(db, .{ .title = "a", .tags = &.{"x"} });
    try db.run("DELETE FROM notes WHERE id = ?", .{1});
    var stmt = try db.prepare("SELECT count(*) FROM note_tags");
    defer stmt.deinit();
    try testing.expect(try stmt.step());
    try testing.expectEqual(@as(i64, 0), stmt.columnInt(0));

    const next = try insert(db, .{ .title = "b" });
    try testing.expectEqual(@as(i64, 2), next.id);
}
